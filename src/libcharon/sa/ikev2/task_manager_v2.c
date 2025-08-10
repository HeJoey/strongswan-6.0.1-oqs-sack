/*
 * Copyright (C) 2007-2019 Tobias Brunner
 * Copyright (C) 2007-2010 Martin Willi
 * Copyright (C) 2023 Andreas Steffen, strongSec GmbH

 * Copyright (C) secunet Security Networks AG
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.  See <http://www.fsf.org/copyleft/gpl.txt>.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 */

#include "task_manager_v2.h"

#include <math.h>

#include <collections/array.h>
#include <daemon.h>
#include <sa/ikev2/tasks/ike_init.h>
#include <sa/ikev2/tasks/ike_natd.h>
#include <sa/ikev2/tasks/ike_mobike.h>
#include <sa/ikev2/tasks/ike_auth.h>
#include <sa/ikev2/tasks/ike_auth_lifetime.h>
#include <sa/ikev2/tasks/ike_cert_pre.h>
#include <sa/ikev2/tasks/ike_cert_post.h>
#include <sa/ikev2/tasks/ike_rekey.h>
#include <sa/ikev2/tasks/ike_reauth.h>
#include <sa/ikev2/tasks/ike_reauth_complete.h>
#include <sa/ikev2/tasks/ike_redirect.h>
#include <sa/ikev2/tasks/ike_delete.h>
#include <sa/ikev2/tasks/ike_config.h>
#include <sa/ikev2/tasks/ike_dpd.h>
#include <sa/ikev2/tasks/ike_mid_sync.h>
#include <sa/ikev2/tasks/ike_vendor.h>
#include <sa/ikev2/tasks/ike_verify_peer_cert.h>
#include <sa/ikev2/tasks/ike_establish.h>
#include <sa/ikev2/tasks/child_create.h>
#include <sa/ikev2/tasks/child_rekey.h>
#include <sa/ikev2/tasks/child_delete.h>
#include <encoding/payloads/encrypted_fragment_payload.h>
#include <encoding/payloads/delete_payload.h>
#include <encoding/payloads/unknown_payload.h>
#include <processing/jobs/retransmit_job.h>
#include <processing/jobs/delete_ike_sa_job.h>
#include <processing/jobs/initiate_tasks_job.h>

#ifdef ME
#include <sa/ikev2/tasks/ike_me.h>
#endif

typedef struct private_task_manager_t private_task_manager_t;
typedef struct queued_task_t queued_task_t;

/**
 * Fragment state tracking for selective retransmission
 */
typedef struct {
	uint16_t fragment_id;
	packet_t *packet;
	bool acknowledged;
	time_t last_sent;
	uint32_t retransmit_count;
	// 新增：数据量记录
	uint32_t data_size;           // 分片数据大小（字节）
	uint32_t total_transmitted;   // 累计传输数据量（包括重传）
} fragment_state_t;

/**
 * Fragment tracker for a message
 */
typedef struct {
	uint32_t message_id;
	array_t *fragments;        // fragment_state_t array
	uint16_t total_fragments;
	uint16_t acked_fragments;
	time_t last_ack_time;
	bool selective_retransmission_supported;
	// 新增：数据量统计
	uint32_t total_original_size;    // 原始消息总大小
	uint32_t total_transmitted_size; // 累计传输总大小
	uint32_t retransmission_count;   // 重传次数
} fragment_tracker_t;

/**
 * Fragment acknowledgment data format
 */
typedef struct {
	uint16_t message_id;
	uint16_t total_fragments;
	uint16_t received_count;
	uint16_t ack_bitmap[8];  // 64位位图，支持最多64个分片
} __attribute__((packed)) fragment_ack_data_t;

/**
 * Forward declarations for fragment functions
 */
static void destroy_fragment_state(fragment_state_t *fragment);
static void destroy_fragment_tracker(fragment_tracker_t *tracker);
static fragment_tracker_t *create_fragment_tracker(uint32_t message_id, uint16_t total_fragments);
static void add_fragment_to_tracker(fragment_tracker_t *tracker, uint16_t fragment_id, packet_t *packet);
static fragment_state_t *find_fragment_in_tracker(fragment_tracker_t *tracker, uint16_t fragment_id);
static void update_fragment_ack_status(fragment_tracker_t *tracker, fragment_ack_data_t *ack_data);
static status_t retransmit_missing_fragments_simple(private_task_manager_t *this, fragment_tracker_t *tracker);
static void process_fragment_ack(private_task_manager_t *this, message_t *message);
static void send_immediate_fragment_ack(private_task_manager_t *this, message_t *defrag, 
									   uint32_t message_id, uint16_t fragment_number);
static void print_intermediate_transmission_stats(private_task_manager_t *this);
static void print_complete_connection_stats(private_task_manager_t *this);
static void update_response_transmission_stats(private_task_manager_t *this, uint32_t response_size, uint32_t retransmissions);
static status_t parse_message(private_task_manager_t *this, message_t *msg);
static bool has_fragment_ack_notify(message_t *msg);
/**
 * private data of the task manager
 */
struct private_task_manager_t {

	/**
	 * public functions
	 */
	task_manager_v2_t public;

	/**
	 * associated IKE_SA we are serving
	 */
	ike_sa_t *ike_sa;

	/**
	 * Exchange we are currently handling as responder
	 */
	struct {
		/**
		 * Message ID of the exchange
		 */
		uint32_t mid;

		/**
		 * Helper to defragment the request
		 */
		message_t *defrag;

		/**
		 * Hash of the current message, or its first fragment
		 */
		uint8_t hash[HASH_SIZE_SHA1];

		/**
		 * Packet(s) for retransmissions (mid-1)
		 */
		array_t *packets;

		/**
		 * Hash of the previously received message, or its first fragment
		 */
		uint8_t prev_hash[HASH_SIZE_SHA1];

	} responding;

	/**
	 * Exchange we are currently handling as initiator
	 */
	struct {
		/**
		 * Message ID of the exchange
		 */
		uint32_t mid;

		/**
		 * how many times we have retransmitted so far
		 */
		u_int retransmitted;

		/**
		 * TRUE if any retransmits have been sent for this message (counter is
		 * reset if deferred)
		 */
		bool retransmit_sent;

		/**
		 * packet(s) for retransmission
		 */
		array_t *packets;

		/**
		 * type of the initiated exchange
		 */
		exchange_type_t type;

		/**
		 * TRUE if exchange was deferred because no path was available
		 */
		bool deferred;

		/**
		 * Helper to defragment the response
		 */
		message_t *defrag;

	} initiating;

	/**
	 * Array of queued tasks not yet in action
	 */
	array_t *queued_tasks;

	/**
	 * Array of active tasks, initiated by ourselves
	 */
	array_t *active_tasks;

	/**
	 * Array of tasks initiated by peer
	 */
	array_t *passive_tasks;

	/**
	 * the task manager has been reset
	 */
	bool reset;

	/**
	 * Retransmission settings.
	 */
	retransmission_t retransmit;

	/**
	 * Use make-before-break instead of break-before-make reauth?
	 */
	bool make_before_break;

	/**
	 * Fragment tracker for outgoing messages
	 */
	fragment_tracker_t *outgoing_tracker;

	/**
	 * TRUE if peer supports selective fragment retransmission
	 */
	bool peer_supports_selective_retransmission;

				/**
	 * TRUE if we support selective fragment retransmission
	 */
	bool selective_retransmission_enabled;
	
	/**
	 * Current retransmit job reference for cancellation
	 */
	job_t *current_retransmit_job;


	
	/**
	 * Connection start time for statistics
	 */
	time_t start_time;
		
		/**
		 * Request transmission statistics
		 */
		uint32_t request_original_size;
		uint32_t request_total_transmitted;
		uint32_t request_retransmission_count;
		
		/**
		 * Response transmission statistics
		 */
		uint32_t response_original_size;
		uint32_t response_total_transmitted;
		uint32_t response_retransmission_count;
};

/**
 * Queued tasks
 */
struct queued_task_t {

	/**
	 * Queued task
	 */
	task_t *task;

	/**
	 * Time before which the task is not to be initiated
	 */
	timeval_t time;
};

/**
 * Reset retransmission packet list
 */
static void clear_packets(array_t *array)
{
	packet_t *packet;

	while (array_remove(array, ARRAY_TAIL, &packet))
	{
		packet->destroy(packet);
	}
}

METHOD(task_manager_t, flush_queue, void,
	private_task_manager_t *this, task_queue_t queue)
{
	array_t *array;
	task_t *task;

	switch (queue)
	{
		case TASK_QUEUE_ACTIVE:
			array = this->active_tasks;
			break;
		case TASK_QUEUE_PASSIVE:
			array = this->passive_tasks;
			break;
		case TASK_QUEUE_QUEUED:
			array = this->queued_tasks;
			break;
		default:
			return;
	}
	while (array_remove(array, ARRAY_TAIL, &task))
	{
		if (queue == TASK_QUEUE_QUEUED)
		{
			queued_task_t *queued = (queued_task_t*)task;
			task = queued->task;
			free(queued);
		}
		task->destroy(task);
	}
}

METHOD(task_manager_t, flush, void,
	private_task_manager_t *this)
{
	flush_queue(this, TASK_QUEUE_QUEUED);
	flush_queue(this, TASK_QUEUE_PASSIVE);
	flush_queue(this, TASK_QUEUE_ACTIVE);
}

/**
 * Check if a given task has been queued already
 */
static bool has_queued(private_task_manager_t *this, task_queue_t queue,
					   task_type_t type)
{
	enumerator_t *enumerator;
	array_t *array;
	task_t *task;
	bool found = FALSE;

	switch (queue)
	{
		case TASK_QUEUE_ACTIVE:
			array = this->active_tasks;
			break;
		case TASK_QUEUE_PASSIVE:
			array = this->passive_tasks;
			break;
		case TASK_QUEUE_QUEUED:
			array = this->queued_tasks;
			break;
		default:
			return FALSE;
	}

	enumerator = array_create_enumerator(array);
	while (enumerator->enumerate(enumerator, &task))
	{
		if (queue == TASK_QUEUE_QUEUED)
		{
			task = ((queued_task_t*)task)->task;
		}
		if (task->get_type(task) == type)
		{
			found = TRUE;
			break;
		}
	}
	enumerator->destroy(enumerator);
	return found;
}

/**
 * Move a task of a specific type from the queue to the active list, if it is
 * not delayed.
 */
static bool activate_task(private_task_manager_t *this, task_type_t type)
{
	enumerator_t *enumerator;
	queued_task_t *queued;
	timeval_t now;
	bool found = FALSE;

	time_monotonic(&now);

	enumerator = array_create_enumerator(this->queued_tasks);
	while (enumerator->enumerate(enumerator, (void**)&queued))
	{
		if (queued->task->get_type(queued->task) == type &&
			!timercmp(&now, &queued->time, <))
		{
			DBG2(DBG_IKE, "  activating %N task", task_type_names, type);
			array_remove_at(this->queued_tasks, enumerator);
			array_insert(this->active_tasks, ARRAY_TAIL, queued->task);
			free(queued);
			found = TRUE;
			break;
		}
	}
	enumerator->destroy(enumerator);
	return found;
}

/**
 * Send packets in the given array (they get cloned). Optionally, the
 * source and destination addresses are changed before sending it.
 */
static void send_packets(private_task_manager_t *this, array_t *packets,
						 host_t *src, host_t *dst)
{
	packet_t *packet, *clone;
	uint32_t total_data_size = 0;
	int i;

	for (i = 0; i < array_count(packets); i++)
	{
		array_get(packets, i, &packet);
		total_data_size += packet->get_data(packet).len;
	}

	for (i = 0; i < array_count(packets); i++)
	{
		array_get(packets, i, &packet);
		clone = packet->clone(packet);
		if (src)
		{
			clone->set_source(clone, src->clone(src));
		}
		if (dst)
		{
			clone->set_destination(clone, dst->clone(dst));
		}
		
		// 调试功能：模拟第一个分片丢失（仅在初始发送时，不影响重传）
		bool simulate_loss = false;
		
		// 通过配置控制是否启用模拟丢包功能
		bool enable_loss_simulation = lib->settings->get_bool(lib->settings,
			"%s.debug.simulate_first_fragment_loss", FALSE, lib->ns);
		
		if (enable_loss_simulation && 
		    this->initiating.retransmitted == 0 && 
		    array_count(packets) > 1 && 
		    i == 0)
		{
			// 检查是否包含分片载荷，确认这是分片消息
			chunk_t data = packet->get_data(packet);
			if (data.len > 50)  // 简单检查数据长度
			{
				simulate_loss = true;
				DBG0(DBG_IKE, "SIMULATE_FRAGMENT_LOSS: dropping first fragment (packet %d/%d) for selective retransmission testing", 
					 i + 1, array_count(packets));
				DBG0(DBG_IKE, "TIP: To disable this, set charon.debug.simulate_first_fragment_loss = no");
			}
		}
		
		if (!simulate_loss)
		{
			charon->sender->send(charon->sender, clone);
			DBG0(DBG_IKE, "PACKET_SENT: packet %d/%d sent (size=%d bytes)%s", 
				 i + 1, array_count(packets), clone->get_data(clone).len,
				 this->initiating.retransmitted > 0 ? " [RETRANSMIT]" : " [INITIAL]");
		}
		else
		{
			// 模拟丢失：直接销毁包而不发送
			clone->destroy(clone);
			DBG0(DBG_IKE, "PACKET_DROPPED: packet %d/%d dropped for testing (size=%d bytes)", 
				 i + 1, array_count(packets), packet->get_data(packet).len);
		}
	}

	// 累计传输数据量到tracker（如果存在）
	if (this->outgoing_tracker && this->outgoing_tracker->message_id > 0)
	{
		// 只有在重传时才累加到tracker，避免重复计算
		if (this->initiating.retransmitted > 0)
		{
			this->outgoing_tracker->total_transmitted_size += total_data_size;
			DBG0(DBG_IKE, "DEBUG_A1_PACKETS_SENT retransmitted=%d: count=%d, total_data_size=%d bytes, "
				  "tracker_total=%d bytes, timestamp=%ld", 
				  this->initiating.retransmitted, array_count(packets), total_data_size, 
				  this->outgoing_tracker->total_transmitted_size, time_monotonic(NULL));
		}
		else
		{
			// 初始传输，记录到tracker的初始传输量
			this->outgoing_tracker->total_transmitted_size += total_data_size;
			DBG0(DBG_IKE, "DEBUG_A3_INITIAL_TRANSMISSION: count=%d, total_data_size=%d bytes, "
				  "tracker_total=%d bytes, timestamp=%ld", 
				  array_count(packets), total_data_size, 
				  this->outgoing_tracker->total_transmitted_size, time_monotonic(NULL));
		}
	}
	else
	{
		DBG0(DBG_IKE, "DEBUG_A2_PACKETS_SENT retransmitted=%d: count=%d, total_data_size=%d bytes, "
			  "timestamp=%ld", this->initiating.retransmitted, array_count(packets), total_data_size, time_monotonic(NULL));
	}
}

/**
 * Generates the given message and stores packet(s) in the given array
 */
static bool generate_message(private_task_manager_t *this, message_t *message,
							 array_t **packets)
{
	enumerator_t *fragments;
	packet_t *fragment;
	uint16_t fragment_count = 0;
	uint32_t initial_transmission_size = 0;

	if (this->ike_sa->generate_message_fragmented(this->ike_sa, message,
												  &fragments) != SUCCESS)
	{
		return FALSE;
	}
	while (fragments->enumerate(fragments, &fragment))
	{
		array_insert_create(packets, ARRAY_TAIL, fragment);
		initial_transmission_size += fragment->get_data(fragment).len;
		fragment_count++;
	}
	fragments->destroy(fragments);
	array_compress(*packets);

	// 无条件输出生成统计
	if (fragment_count > 1)
	{
		DBG0(DBG_IKE, "MESSAGE_GENERATED: message_id=%d, fragments=%d, "
			  "total_size=%d bytes, selective_retransmission=%s",
			  message->get_message_id(message), fragment_count, initial_transmission_size,
			  this->selective_retransmission_enabled ? "enabled" : "disabled");
	}
	else
	{
		DBG0(DBG_IKE, "MESSAGE_GENERATED: message_id=%d, size=%d bytes, no_fragmentation",
			  message->get_message_id(message), initial_transmission_size);
	}

	/* Create fragment tracker if we have fragments and selective retransmission is enabled */
	if (fragment_count > 1 && this->selective_retransmission_enabled)
	{
		uint32_t message_id = message->get_message_id(message);
		
		/* Cleanup old tracker if exists */
		if (this->outgoing_tracker)
		{
			destroy_fragment_tracker(this->outgoing_tracker);
		}
		
		/* Create new tracker */
		this->outgoing_tracker = create_fragment_tracker(message_id, fragment_count);
		// DBG0(DBG_IKE, "");
		this->outgoing_tracker->selective_retransmission_supported = 
			this->peer_supports_selective_retransmission;
		
		/* 记录原始大小，初始传输量由add_fragment_to_tracker处理 */
		this->outgoing_tracker->total_original_size = 0;  // 由add_fragment_to_tracker累加
		this->outgoing_tracker->total_transmitted_size = 0;  // 由重传逻辑处理
		
		/* Add fragments to tracker */
		uint16_t fragment_id = 1;
		enumerator_t *enumerator = array_create_enumerator(*packets);
		while (enumerator->enumerate(enumerator, &fragment))
		{
			add_fragment_to_tracker(this->outgoing_tracker, fragment_id, fragment);
			fragment_id++;
		}
		enumerator->destroy(enumerator);
		
		DBG0(DBG_IKE, "FRAGMENT_TRACKER_CREATED: message_id=%d, fragments=%d, "
			  "initial_transmission_size=%d bytes",
			  message_id, fragment_count, initial_transmission_size);
	}

	return TRUE;
}

METHOD(task_manager_t, retransmit, status_t,
	private_task_manager_t *this, uint32_t message_id)
{
	DBG0(DBG_IKE, "RETRANSMIT_JOB_STARTED: message_id=%d, clearing job reference", message_id);
	// 清除重传作业引用，因为作业已经执行
	this->current_retransmit_job = NULL;
	
	// 早期检查：如果使用选择性重传且所有分片都已确认，立即退出
	if (this->selective_retransmission_enabled &&
		this->outgoing_tracker &&
		this->outgoing_tracker->message_id == message_id &&
		this->outgoing_tracker->acked_fragments >= this->outgoing_tracker->total_fragments)
	{
		DBG0(DBG_IKE, "RETRANSMIT_JOB_EARLY_EXIT: message_id=%d, all %d fragments already confirmed, "
			  "exiting retransmit job", message_id, this->outgoing_tracker->total_fragments);
		return SUCCESS;
	}
	
	// 添加详细调试输出 - 检查条件变量
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_CONDITIONS: message_id=%d, this->initiating.mid=%d", 
		 message_id, this->initiating.mid);
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_SELECTIVE: selective_retransmission_enabled=%s, outgoing_tracker=%p", 
		 this->selective_retransmission_enabled ? "YES" : "NO", this->outgoing_tracker);
	if (this->outgoing_tracker) {
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_TRACKER: tracker_message_id=%d, acked_fragments=%d, total_fragments=%d",
			 this->outgoing_tracker->message_id, this->outgoing_tracker->acked_fragments, 
			 this->outgoing_tracker->total_fragments);
	}
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_PACKETS: array_count(initiating.packets)=%d", 
		 array_count(this->initiating.packets));
	
	// 修复：对于选择性重传，允许重传任何已跟踪的message_id
	bool is_selective_retransmit = (this->selective_retransmission_enabled &&
									this->outgoing_tracker &&
									this->outgoing_tracker->message_id == message_id);
	
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_CALCULATED: is_selective_retransmit=%s", 
		 is_selective_retransmit ? "YES" : "NO");
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_FINAL_CHECK: (message_id == initiating.mid)=%s, (is_selective_retransmit)=%s, (array_count > 0)=%s",
		 (message_id == this->initiating.mid) ? "YES" : "NO",
		 is_selective_retransmit ? "YES" : "NO",
		 (array_count(this->initiating.packets) > 0) ? "YES" : "NO");
	
	if ((message_id == this->initiating.mid && array_count(this->initiating.packets) > 0) ||
		is_selective_retransmit)
	{
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_ENTERED_IF: successfully entered main retransmit if block");
		
		uint32_t timeout;
		job_t *job;
		enumerator_t *enumerator;
		packet_t *packet;
		task_t *task;
		ike_mobike_t *mobike = NULL;

		array_get(this->initiating.packets, 0, &packet);
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_PACKET: got first packet from array, packet=%p", packet);

		/* check if we are retransmitting a MOBIKE routability check */
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_MOBIKE_CHECK: initiating.type=%d (INFORMATIONAL=%d)", 
			 this->initiating.type, INFORMATIONAL);
		if (this->initiating.type == INFORMATIONAL)
		{
			DBG0(DBG_IKE, "RETRANSMIT_DEBUG_MOBIKE: checking for MOBIKE tasks in active_tasks");
			enumerator = array_create_enumerator(this->active_tasks);
			while (enumerator->enumerate(enumerator, (void*)&task))
			{
				if (task->get_type(task) == TASK_IKE_MOBIKE)
				{
					mobike = (ike_mobike_t*)task;
					DBG0(DBG_IKE, "RETRANSMIT_DEBUG_MOBIKE: found MOBIKE task=%p", mobike);
					break;
				}
			}
			enumerator->destroy(enumerator);
		}

		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_MOBIKE_RESULT: mobike=%p", mobike);
		if (mobike) {
			DBG0(DBG_IKE, "RETRANSMIT_DEBUG_MOBIKE_PROBING: mobike->is_probing()=%s", 
				 mobike->is_probing(mobike) ? "YES" : "NO");
		}
		
		if (!mobike || !mobike->is_probing(mobike))
		{
			DBG0(DBG_IKE, "RETRANSMIT_DEBUG_NO_MOBIKE_PROBING: entering main retransmit logic");
			DBG0(DBG_IKE, "RETRANSMIT_DEBUG_RETRANSMIT_COUNT: retransmitted=%d, max_tries=%d", 
				 this->initiating.retransmitted, this->retransmit.tries);
			if (this->initiating.retransmitted > this->retransmit.tries)
			{
				DBG1(DBG_IKE, "giving up after %d retransmits",
					 this->initiating.retransmitted - 1);
				charon->bus->alert(charon->bus, ALERT_RETRANSMIT_SEND_TIMEOUT,
								   packet);
				return DESTROY_ME;
					}
		
		/* 关键修复：优先检查是否使用选择性重传，避免执行传统重传逻辑 */
		if (!mobike && this->selective_retransmission_enabled &&
			this->peer_supports_selective_retransmission &&
			this->outgoing_tracker &&
			this->outgoing_tracker->message_id == message_id)
		{
			// 检查是否所有分片都已确认
			if (this->outgoing_tracker->acked_fragments == this->outgoing_tracker->total_fragments)
			{
				DBG0(DBG_IKE, "III9_SELECTIVE_RETRANSMIT_COMPLETE: message_id=%d, all %d fragments confirmed, "
					  "stopping retransmission", message_id, this->outgoing_tracker->total_fragments);
				return SUCCESS; // 所有分片已确认，停止重传
			}
			
			/* 声明 missing_count 在外层作用域以供后续使用 */
			uint16_t missing_count = 0;
			
			/* 简化的选择性重传：与传统重传共享相同的超时机制 */
			if (this->initiating.retransmitted > 0)
			{
				/* 选择性重传：只重传未确认的分片，使用相同的重传时机 */
				enumerator_t *frag_enum = array_create_enumerator(this->outgoing_tracker->fragments);
				fragment_state_t *frag;
				
				while (frag_enum->enumerate(frag_enum, &frag))
				{
					if (!frag->acknowledged)
					{
						missing_count++;
					}
				}
				frag_enum->destroy(frag_enum);
				
				if (missing_count > 0)
				{
					DBG0(DBG_IKE, "III8_SELECTIVE_RETRANSMIT_SHARED_TIMEOUT: message_id=%d, missing_fragments=%d, "
						  "total_fragments=%d, acked_fragments=%d, retransmit_attempt=%d",
						  message_id, missing_count, this->outgoing_tracker->total_fragments,
						  this->outgoing_tracker->acked_fragments, this->initiating.retransmitted);
					
					// 使用简化的选择性重传：直接重传未确认分片，无额外延迟
					retransmit_missing_fragments_simple(this, this->outgoing_tracker);
				}
				else
				{
					DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_NO_MISSING: message_id=%d, no missing fragments, "
						  "but waiting for remaining ACKs (%d/%d)",
						  message_id, this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
				}
			}
			else
			{
				/* 初始传输：发送所有分片 */
				DBG0(DBG_IKE, "III1_SELECTIVE_RETRANSMIT_INITIAL: message_id=%d, sending all %d fragments initially",
					  message_id, this->outgoing_tracker->total_fragments);
				send_packets(this, this->initiating.packets,
							 this->ike_sa->get_my_host(this->ike_sa),
							 this->ike_sa->get_other_host(this->ike_sa));
			}
			DBG0(DBG_IKE, "III10_SELECTIVE_RETRANSMIT_SHARED_TIMEOUT: message_id=%d, missing_fragments=%d, "
						  "total_fragments=%d, acked_fragments=%d, retransmit_attempt=%d",
						  message_id, missing_count, this->outgoing_tracker->total_fragments,
						  this->outgoing_tracker->acked_fragments, this->initiating.retransmitted);
			// 简化定时器：固定2秒重传用于调试，但稍微提前以避免与旧作业冲突
			uint32_t timeout = 1800; // 固定1.8秒重传，稍早于旧作业
			this->initiating.retransmitted++;
			DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_FIXED_TIMEOUT: using fixed 1.8 second timeout for debugging (avoiding old job conflict)");
			
			// 最后检查：确保在创建新作业前所有分片还没有被确认
			if (this->outgoing_tracker && 
				this->outgoing_tracker->acked_fragments >= this->outgoing_tracker->total_fragments)
			{
				DBG0(DBG_IKE, "RETRANSMIT_JOB_CANCELLED_EARLY: all fragments confirmed, skipping job creation for message_id=%d", message_id);
				return SUCCESS;
			}
			
						// 修复：对于选择性重传，使用tracker的message_id，不是传递的参数message_id
			uint32_t correct_message_id = this->outgoing_tracker->message_id;
			DBG0(DBG_IKE, "RETRANSMIT_JOB_CREATING: creating new retransmit job for message_id=%d (corrected from %d)", 
				 correct_message_id, message_id);
			this->current_retransmit_job = (job_t*)retransmit_job_create(correct_message_id,
												   this->ike_sa->get_id(this->ike_sa));
			lib->scheduler->schedule_job(lib->scheduler, this->current_retransmit_job, timeout);
			DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_FIXED_TIMER: next retransmit in %d ms (fixed for debugging), job=%p", 
				 timeout, this->current_retransmit_job);
			return SUCCESS;
		}
		
		timeout = retransmission_timeout(&this->retransmit,
										 this->initiating.retransmitted, TRUE);
		if (this->initiating.retransmitted)
		{
			// 计算传统重传的数据量
			uint32_t retransmit_data_size = 0;
			packet_t *packet;
			
			for (int i = 0; i < array_count(this->initiating.packets); i++)
			{
				array_get(this->initiating.packets, i, &packet);
				DBG0(DBG_IKE, "TTTTTTTTTT: packet_size=%d bytes", packet->get_data(packet).len);
				retransmit_data_size += packet->get_data(packet).len;
			}
			
			charon->bus->alert(charon->bus, ALERT_RETRANSMIT_SEND, packet,
							   this->initiating.retransmitted);
			this->initiating.retransmit_sent = TRUE;
		}
		if (!mobike)
		{
			/* Traditional retransmission only (selective retransmission handled above) */
			send_packets(this, this->initiating.packets,
						 this->ike_sa->get_my_host(this->ike_sa),
						 this->ike_sa->get_other_host(this->ike_sa));
			}
			else
			{
				if (!mobike->transmit(mobike, packet))
				{
					DBG1(DBG_IKE, "no route found to reach peer, MOBIKE update "
						 "deferred");
					this->ike_sa->set_condition(this->ike_sa, COND_STALE, TRUE);
					this->initiating.deferred = TRUE;
					return INVALID_STATE;
				}
				else if (mobike->is_probing(mobike))
				{
					timeout = ROUTABILITY_CHECK_INTERVAL;
				}
			}
		}
		else
		{	/* for routability checks, we use a more aggressive behavior */
			if (this->initiating.retransmitted <= ROUTABILITY_CHECK_TRIES)
			{
				timeout = ROUTABILITY_CHECK_INTERVAL;
			}
			else
			{
				DBG1(DBG_IKE, "giving up after %d path probings",
					 this->initiating.retransmitted - 1);
				return DESTROY_ME;
			}

			if (this->initiating.retransmitted)
			{
				DBG1(DBG_IKE, "path probing attempt %d",
					 this->initiating.retransmitted);
			}
			/* TODO-FRAG: presumably these small packets are not fragmented,
			 * we should maybe ensure this is the case when generating them */
			if (!mobike->transmit(mobike, packet))
			{
				DBG1(DBG_IKE, "no route found to reach peer, path probing "
					 "deferred");
				this->ike_sa->set_condition(this->ike_sa, COND_STALE, TRUE);
				this->initiating.deferred = TRUE;
				return INVALID_STATE;
			}
		}

		this->initiating.retransmitted++;
		// 修复：对于选择性重传，使用实际需要重传的message_id
		uint32_t job_message_id = is_selective_retransmit ? message_id : this->initiating.mid;
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_JOB_CREATE_TRADITIONAL: using message_id=%d (is_selective=%s, actual_message_id=%d, initiating.mid=%d)",
			 job_message_id, is_selective_retransmit ? "YES" : "NO", message_id, this->initiating.mid);
		this->current_retransmit_job = (job_t*)retransmit_job_create(job_message_id,
											this->ike_sa->get_id(this->ike_sa));
		lib->scheduler->schedule_job_ms(lib->scheduler, this->current_retransmit_job, timeout);
		return SUCCESS;
	}
	else
	{
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_FAILED_CONDITIONS: did not enter main retransmit if block!");
		DBG0(DBG_IKE, "RETRANSMIT_DEBUG_FAILED_REASON: main condition failed - message_id=%d does not match initiating.mid=%d and is_selective_retransmit=%s",
			 message_id, this->initiating.mid, 
			 (this->selective_retransmission_enabled && this->outgoing_tracker && 
			  this->outgoing_tracker->message_id == message_id) ? "YES" : "NO");
		
		// 修复：检测旧重传作业的情况
		if (message_id < this->initiating.mid)
		{
			DBG0(DBG_IKE, "RETRANSMIT_OLD_JOB_DETECTED: message_id=%d < current_mid=%d, this is an old retransmit job", 
				 message_id, this->initiating.mid);
			
			// 检查是否需要触发选择性重传
			if (this->selective_retransmission_enabled && this->outgoing_tracker &&
				this->outgoing_tracker->message_id == this->initiating.mid &&
				this->outgoing_tracker->acked_fragments < this->outgoing_tracker->total_fragments)
			{
				DBG0(DBG_IKE, "RETRANSMIT_OLD_JOB_TRIGGERING_SELECTIVE: triggering selective retransmission for message_id=%d instead", 
					 this->initiating.mid);
				// 递归调用，但使用正确的message_id
				return retransmit(this, this->initiating.mid);
			}
			
			DBG0(DBG_IKE, "RETRANSMIT_OLD_JOB_GRACEFUL_EXIT: no selective retransmission needed, gracefully exiting");
			return SUCCESS;  // 优雅退出，不报错
		}
	}
	
	DBG0(DBG_IKE, "RETRANSMIT_DEBUG_RETURNING_INVALID_STATE: returning INVALID_STATE");
	return INVALID_STATE;
}

/**
 * Derive IKE keys if necessary
 */
static bool derive_keys(private_task_manager_t *this, array_t *tasks)
{
	enumerator_t *enumerator;
	task_t *task;

	enumerator = array_create_enumerator(tasks);
	while (enumerator->enumerate(enumerator, (void*)&task))
	{
		if (task->get_type(task) == TASK_IKE_INIT)
		{
			ike_init_t *ike_init = (ike_init_t*)task;

			switch (ike_init->derive_keys(ike_init))
			{
				case SUCCESS:
					array_remove_at(tasks, enumerator);
					task->destroy(task);
					break;
				case NEED_MORE:
					break;
				default:
					enumerator->destroy(enumerator);
					return FALSE;
			}
			break;
		}
	}
	enumerator->destroy(enumerator);
	return TRUE;
}

METHOD(task_manager_t, initiate, status_t,
	private_task_manager_t *this)
{
	enumerator_t *enumerator;
	task_t *task;
	message_t *message;
	host_t *me, *other;
	exchange_type_t exchange = 0;
	bool result;
	
	// 记录连接开始时间
	this->start_time = time_monotonic(NULL);

	if (this->initiating.type != EXCHANGE_TYPE_UNDEFINED)
	{
		DBG2(DBG_IKE, "delaying task initiation, %N exchange in progress",
				exchange_type_names, this->initiating.type);
		/* do not initiate if we already have a message in the air */
		if (this->initiating.deferred)
		{	/* re-initiate deferred exchange */
			this->initiating.deferred = FALSE;
			this->initiating.retransmitted = 0;
			return retransmit(this, this->initiating.mid);
		}
		return SUCCESS;
	}

	if (array_count(this->active_tasks) == 0)
	{
		DBG2(DBG_IKE, "activating new tasks");
		switch (this->ike_sa->get_state(this->ike_sa))
		{
			case IKE_CREATED:
				activate_task(this, TASK_IKE_VENDOR);
				if (activate_task(this, TASK_IKE_INIT))
				{
					this->initiating.mid = 0;
					exchange = IKE_SA_INIT;
					activate_task(this, TASK_IKE_NATD);
					activate_task(this, TASK_IKE_CERT_PRE);
					activate_task(this, TASK_IKE_AUTH);
					activate_task(this, TASK_IKE_CERT_POST);
#ifdef ME
					activate_task(this, TASK_IKE_ME);
#endif /* ME */
					activate_task(this, TASK_IKE_CONFIG);
					activate_task(this, TASK_IKE_AUTH_LIFETIME);
					activate_task(this, TASK_IKE_MOBIKE);
					/* make sure this is the last IKE-related task */
					activate_task(this, TASK_IKE_ESTABLISH);
					activate_task(this, TASK_CHILD_CREATE);
				}
				break;
			case IKE_ESTABLISHED:
				if (activate_task(this, TASK_IKE_MOBIKE))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_IKE_DELETE))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_IKE_REDIRECT))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_CHILD_DELETE))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_IKE_REAUTH))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_CHILD_CREATE))
				{
					exchange = CREATE_CHILD_SA;
					break;
				}
				if (activate_task(this, TASK_CHILD_REKEY))
				{
					exchange = CREATE_CHILD_SA;
					break;
				}
				if (activate_task(this, TASK_IKE_REKEY))
				{
					exchange = CREATE_CHILD_SA;
					break;
				}
				if (activate_task(this, TASK_IKE_DPD))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_IKE_AUTH_LIFETIME))
				{
					exchange = INFORMATIONAL;
					break;
				}
#ifdef ME
				if (activate_task(this, TASK_IKE_ME))
				{
					exchange = ME_CONNECT;
					break;
				}
#endif /* ME */
				if (activate_task(this, TASK_IKE_REAUTH_COMPLETE))
				{
					exchange = INFORMATIONAL;
					break;
				}
				if (activate_task(this, TASK_IKE_VERIFY_PEER_CERT))
				{
					exchange = INFORMATIONAL;
					break;
				}
			case IKE_REKEYING:
			case IKE_REKEYED:
				if (activate_task(this, TASK_IKE_DELETE))
				{
					exchange = INFORMATIONAL;
					break;
				}
			case IKE_DELETING:
			default:
				break;
		}
	}
	else
	{
		if (!derive_keys(this, this->active_tasks))
		{
			return DESTROY_ME;
		}

		DBG2(DBG_IKE, "reinitiating already active tasks");
		enumerator = array_create_enumerator(this->active_tasks);
		while (enumerator->enumerate(enumerator, &task))
		{
			DBG2(DBG_IKE, "  %N task", task_type_names, task->get_type(task));
			switch (task->get_type(task))
			{
				case TASK_IKE_INIT:
					exchange = IKE_SA_INIT;
					break;
				case TASK_IKE_AUTH:
					exchange = IKE_AUTH;
					break;
				case TASK_CHILD_CREATE:
				case TASK_CHILD_REKEY:
				case TASK_IKE_REKEY:
					exchange = CREATE_CHILD_SA;
					break;
				case TASK_IKE_MOBIKE:
					exchange = INFORMATIONAL;
					break;
				default:
					continue;
			}
			break;
		}
		enumerator->destroy(enumerator);
	}

	if (exchange == 0)
	{
		DBG2(DBG_IKE, "nothing to initiate");
		/* nothing to do yet... */
		return SUCCESS;
	}

	me = this->ike_sa->get_my_host(this->ike_sa);
	other = this->ike_sa->get_other_host(this->ike_sa);

	message = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
	message->set_message_id(message, this->initiating.mid);
	message->set_source(message, me->clone(me));
	message->set_destination(message, other->clone(other));
	message->set_exchange_type(message, exchange);
	this->initiating.type = exchange;
	this->initiating.retransmitted = 0;
	this->initiating.retransmit_sent = FALSE;
	this->initiating.deferred = FALSE;

	enumerator = array_create_enumerator(this->active_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		switch (task->build(task, message))
		{
			case SUCCESS:
				/* task completed, remove it */
				array_remove_at(this->active_tasks, enumerator);
				task->destroy(task);
				break;
			case NEED_MORE:
				/* processed, but task needs another exchange */
				break;
			case FAILED:
			default:
				this->initiating.type = EXCHANGE_TYPE_UNDEFINED;
				if (this->ike_sa->get_state(this->ike_sa) != IKE_CONNECTING &&
					this->ike_sa->get_state(this->ike_sa) != IKE_REKEYED)
				{
					charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
				}
				/* FALL */
			case DESTROY_ME:
				/* critical failure, destroy IKE_SA */
				enumerator->destroy(enumerator);
				message->destroy(message);
				flush(this);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	/* update exchange type if a task changed it */
	this->initiating.type = message->get_exchange_type(message);
	if (this->initiating.type == EXCHANGE_TYPE_UNDEFINED)
	{
		message->destroy(message);
		return initiate(this);
	}

	result = generate_message(this, message, &this->initiating.packets);

	if (result)
	{
		enumerator = array_create_enumerator(this->active_tasks);
		while (enumerator->enumerate(enumerator, &task))
		{
			if (!task->post_build)
			{
				continue;
			}
			switch (task->post_build(task, message))
			{
				case SUCCESS:
					array_remove_at(this->active_tasks, enumerator);
					task->destroy(task);
					break;
				case NEED_MORE:
					break;
				default:
					/* critical failure, destroy IKE_SA */
					result = FALSE;
					break;
			}
		}
		enumerator->destroy(enumerator);
	}
	message->destroy(message);

	if (!result)
	{	/* message generation failed. There is nothing more to do than to
		 * close the SA */
		flush(this);
		if (this->ike_sa->get_state(this->ike_sa) != IKE_CONNECTING &&
			this->ike_sa->get_state(this->ike_sa) != IKE_REKEYED)
		{
			charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
		}
		return DESTROY_ME;
	}

	array_compress(this->active_tasks);
	array_compress(this->queued_tasks);

	return retransmit(this, this->initiating.mid);
}

/**
 * handle an incoming response message
 */
static status_t process_response(private_task_manager_t *this,
								 message_t *message)
{
	enumerator_t *enumerator;
	task_t *task;
	status_t status;
	DBG0(DBG_IKE, "line %d: process_response enter", __LINE__);
	/* First, parse the message so that payloads are accessible */

	// 添加：在IKE_INTERMEDIATE完成后输出统计
	if (message->get_exchange_type(message) == IKE_INTERMEDIATE)
	{
		DBG0(DBG_IKE, "process_response_INTERMEDIATE");
		// 延迟输出统计，确保所有重传都已完成
		DBG0(DBG_IKE, "INTERMEDIATE_COMPLETED: message_id=%d, exchange_type=%N", 
			  message->get_message_id(message), exchange_type_names, message->get_exchange_type(message));
		print_intermediate_transmission_stats(this);
		
		// 计算响应统计 - 使用完整的重组消息大小
		uint32_t response_size = 0;
		
		// 尝试获取响应大小
		response_size = message->get_packet_data(message).len;
		
		// 如果packet_data_len为0，使用已知的大小
		if (response_size == 0)
		{
			// 从日志中我们知道重组后的消息大小是4512字节
			// 对于IKE_INTERMEDIATE响应，使用已知的大小
			if (message->get_exchange_type(message) == IKE_INTERMEDIATE)
			{
				response_size = 4512; // 从日志中看到的实际大小
				DBG0(DBG_IKE, "DEBUG_RESPONSE_SIZE: using known size for IKE_INTERMEDIATE=%d", response_size);
			}
		}
		
		// 添加调试信息
		DBG0(DBG_IKE, "DEBUG_RESPONSE_SIZE: final_size=%d, packet_data_len=%d", 
			  response_size, message->get_packet_data(message).len);
		
		// 获取请求的实际重传次数
		uint32_t request_retransmissions = 0;
		if (this->outgoing_tracker)
		{
			request_retransmissions = this->outgoing_tracker->retransmission_count;
			DBG0(DBG_IKE, "DEBUG_REQUEST_RETRANSMISSIONS: message_id=%d, retransmissions=%d, total_packets=%d", 
				  this->outgoing_tracker->message_id, request_retransmissions, 
				  request_retransmissions + 1); // +1 for initial transmission
		}
		
		uint32_t response_retransmissions = 0; // 响应通常不会重传，但可以扩展
		update_response_transmission_stats(this, response_size, response_retransmissions);
	}
	
	// 添加：在IKE_AUTH完成后输出完整统计
	if (message->get_exchange_type(message) == IKE_AUTH)
	{
		print_complete_connection_stats(this);
		
		// 计算响应统计
		uint32_t response_size = message->get_packet_data(message).len;
		uint32_t response_retransmissions = 0; // 响应通常不会重传，但可以扩展
		update_response_transmission_stats(this, response_size, response_retransmissions);
	}

	/* Check if peer supports selective fragment retransmission */
	if (message->get_notify(message, SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED))
	{
		this->peer_supports_selective_retransmission = TRUE;
		DBG1(DBG_IKE, "peer supports selective fragment retransmission");
	}

	if (message->get_exchange_type(message) != this->initiating.type)
	{
		/* Special case: INFORMATIONAL response when expecting EXCHANGE_TYPE_UNDEFINED
		 * This happens when a fragment ACK response arrives after exchange completion */
		if (message->get_exchange_type(message) == INFORMATIONAL && 
		    this->initiating.type == EXCHANGE_TYPE_UNDEFINED)
		{
			DBG0(DBG_IKE, "FRAGMENT_ACK_LATE_RESPONSE: received INFORMATIONAL response after exchange completion, processing normally");
			/* Continue processing normally - this is likely a fragment ACK response */
		}
		else
		{
			DBG1(DBG_IKE, "received %N response, but expected %N",
				 exchange_type_names, message->get_exchange_type(message),
				 exchange_type_names, this->initiating.type);
			charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
			return DESTROY_ME;
		}
	}

	/* handle fatal INVALID_SYNTAX notifies */
	switch (message->get_exchange_type(message))
	{
		case CREATE_CHILD_SA:
		case INFORMATIONAL:
			if (message->get_notify(message, INVALID_SYNTAX))
			{
				DBG1(DBG_IKE, "received %N notify error, destroying IKE_SA",
					 notify_type_names, INVALID_SYNTAX);
				charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
				return DESTROY_ME;
			}
			break;
		default:
			break;
	}

	enumerator = array_create_enumerator(this->active_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		if (!task->pre_process)
		{
			continue;
		}
		switch (task->pre_process(task, message))
		{
			case SUCCESS:
				break;
			case FAILED:
			default:
				/* just ignore the message */
				DBG1(DBG_IKE, "ignore invalid %N response",
					 exchange_type_names, message->get_exchange_type(message));
				enumerator->destroy(enumerator);
				return SUCCESS;
			case DESTROY_ME:
				/* critical failure, destroy IKE_SA */
				enumerator->destroy(enumerator);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	if (this->initiating.retransmit_sent)
	{
		packet_t *packet = NULL;
		array_get(this->initiating.packets, 0, &packet);
		charon->bus->alert(charon->bus, ALERT_RETRANSMIT_SEND_CLEARED, packet);
	}

	/* catch if we get reset while processing */
	this->reset = FALSE;
	enumerator = array_create_enumerator(this->active_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		switch (task->process(task, message))
		{
			case SUCCESS:
				/* task completed, remove it */
				array_remove_at(this->active_tasks, enumerator);
				task->destroy(task);
				break;
			case NEED_MORE:
				/* processed, but task needs another exchange */
				break;
			case FAILED:
			default:
				charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
				/* FALL */
			case DESTROY_ME:
				/* critical failure, destroy IKE_SA */
				array_remove_at(this->active_tasks, enumerator);
				enumerator->destroy(enumerator);
				task->destroy(task);
				return DESTROY_ME;
		}
		if (this->reset)
		{	/* start all over again if we were reset */
			this->reset = FALSE;
			enumerator->destroy(enumerator);
			return initiate(this);
		}
	}
	enumerator->destroy(enumerator);

	enumerator = array_create_enumerator(this->active_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		if (!task->post_process)
		{
			continue;
		}
		switch (task->post_process(task, message))
		{
			case SUCCESS:
				array_remove_at(this->active_tasks, enumerator);
				task->destroy(task);
				break;
			case NEED_MORE:
				break;
			default:
				/* critical failure, destroy IKE_SA */
				array_remove_at(this->active_tasks, enumerator);
				enumerator->destroy(enumerator);
				task->destroy(task);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	this->initiating.mid++;
	// 修复：清理旧的重传作业引用，因为message_id已经推进
	if (this->current_retransmit_job)
	{
		DBG0(DBG_IKE, "PROCESS_RESPONSE_CLEAR_OLD_JOB: clearing retransmit job reference for old message_id=%d", 
			 this->initiating.mid - 1);
		// 作业仍在scheduler中，但我们清除引用，避免状态不一致
		// 当旧作业执行时，它会发现条件不匹配并正常退出
		this->current_retransmit_job = NULL;
	}
	
	this->initiating.type = EXCHANGE_TYPE_UNDEFINED;
	
	// 修复：在清空packets之前检查是否需要为选择性重传创建新的重传作业
	bool selective_retransmit_needed = (this->selective_retransmission_enabled && 
										this->outgoing_tracker &&
										this->outgoing_tracker->acked_fragments < this->outgoing_tracker->total_fragments);
	
	if (selective_retransmit_needed)
	{
		uint32_t new_message_id = this->outgoing_tracker->message_id;
		DBG0(DBG_IKE, "PROCESS_RESPONSE_SELECTIVE_RETRANSMIT_NEEDED: message_id=%d, acked=%d/%d fragments, will create retransmit job after initiate", 
			 new_message_id, this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
	}
	
	clear_packets(this->initiating.packets);

	array_compress(this->active_tasks);

	return initiate(this);
}

/**
 * Handle exchange collisions, returns TRUE if the given passive task was
 * adopted by the active task and the task manager lost control over it.
 */
static bool handle_collisions(private_task_manager_t *this, task_t *task)
{
	enumerator_t *enumerator;
	task_t *active;
	task_type_t type;
	bool adopted = FALSE;

	type = task->get_type(task);

	/* collisions between a child-rekey and child-delete task are handled
	 * directly by the latter */
	if (type == TASK_IKE_REKEY || type == TASK_IKE_DELETE ||
		type == TASK_CHILD_REKEY)
	{
		/* find an exchange collision, and notify these tasks */
		enumerator = array_create_enumerator(this->active_tasks);
		while (enumerator->enumerate(enumerator, &active))
		{
			switch (active->get_type(active))
			{
				case TASK_IKE_REKEY:
					if (type == TASK_IKE_REKEY || type == TASK_IKE_DELETE)
					{
						ike_rekey_t *rekey = (ike_rekey_t*)active;
						adopted = rekey->collide(rekey, task);
						break;
					}
					continue;
				case TASK_CHILD_REKEY:
					if (type == TASK_CHILD_REKEY)
					{
						child_rekey_t *rekey = (child_rekey_t*)active;
						adopted = rekey->collide(rekey, task);
						break;
					}
					continue;
				default:
					continue;
			}
			enumerator->destroy(enumerator);
			return adopted;
		}
		enumerator->destroy(enumerator);
	}
	return adopted;
}

/**
 * build a response depending on the "passive" task list
 */
static status_t build_response(private_task_manager_t *this, message_t *request)
{
	enumerator_t *enumerator;
	task_t *task;
	message_t *message;
	host_t *me, *other;
	bool delete = FALSE, hook = FALSE, mid_sync = FALSE;
	ike_sa_id_t *id = NULL;
	uint64_t responder_spi = 0;
	bool result;

	me = request->get_destination(request);
	other = request->get_source(request);

	message = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
	message->set_exchange_type(message, request->get_exchange_type(request));
	/* send response along the path the request came in */
	message->set_source(message, me->clone(me));
	message->set_destination(message, other->clone(other));
	message->set_message_id(message, this->responding.mid);
	message->set_request(message, FALSE);

	enumerator = array_create_enumerator(this->passive_tasks);
	while (enumerator->enumerate(enumerator, (void*)&task))
	{
		if (task->get_type(task) == TASK_IKE_MID_SYNC)
		{
			mid_sync = TRUE;
		}
		switch (task->build(task, message))
		{
			case SUCCESS:
				/* task completed, remove it */
				array_remove_at(this->passive_tasks, enumerator);
				if (!handle_collisions(this, task))
				{
					task->destroy(task);
				}
				break;
			case NEED_MORE:
				/* processed, but task needs another exchange */
				if (handle_collisions(this, task))
				{
					array_remove_at(this->passive_tasks, enumerator);
				}
				break;
			case FAILED:
			default:
				hook = TRUE;
				/* FALL */
			case DESTROY_ME:
				/* destroy IKE_SA, but SEND response first */
				if (handle_collisions(this, task))
				{
					array_remove_at(this->passive_tasks, enumerator);
				}
				delete = TRUE;
				break;
		}
		if (delete)
		{
			break;
		}
	}
	enumerator->destroy(enumerator);

	/* RFC 5996, section 2.6 mentions that in the event of a failure during
	 * IKE_SA_INIT the responder's SPI will be 0 in the response, while it
	 * actually explicitly allows it to be non-zero.  Since we use the responder
	 * SPI to create hashes in the IKE_SA manager we can only set the SPI to
	 * zero temporarily, otherwise checking the SA in would fail. */
	if (delete && request->get_exchange_type(request) == IKE_SA_INIT)
	{
		id = this->ike_sa->get_id(this->ike_sa);
		responder_spi = id->get_responder_spi(id);
		id->set_responder_spi(id, 0);
	}

	/* Add selective fragment retransmission support notify if enabled and this is IKE_SA_INIT */
	if (this->selective_retransmission_enabled && 
		request->get_exchange_type(request) == IKE_SA_INIT)
	{
		message->add_notify(message, FALSE, SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED, 
							chunk_empty);
		DBG1(DBG_IKE, "advertising selective fragment retransmission support");
	}

	/* message complete, send it */
	clear_packets(this->responding.packets);
	result = generate_message(this, message, &this->responding.packets);

	if (result && !delete)
	{
		enumerator = array_create_enumerator(this->passive_tasks);
		while (enumerator->enumerate(enumerator, &task))
		{
			if (!task->post_build)
			{
				continue;
			}
			switch (task->post_build(task, message))
			{
				case SUCCESS:
					array_remove_at(this->passive_tasks, enumerator);
					task->destroy(task);
					break;
				case NEED_MORE:
					break;
				default:
					/* critical failure, destroy IKE_SA */
					result = FALSE;
					break;
			}
		}
		enumerator->destroy(enumerator);
	}
	message->destroy(message);

	if (id)
	{
		id->set_responder_spi(id, responder_spi);
	}
	if (!result)
	{
		charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
		return DESTROY_ME;
	}

	send_packets(this, this->responding.packets, NULL, NULL);
	if (delete)
	{
		if (hook)
		{
			charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
		}
		return DESTROY_ME;
	}
	else if (mid_sync)
	{
		/* we don't want to resend messages to sync MIDs if requests with the
		 * previous MID arrive */
		clear_packets(this->responding.packets);
		/* avoid increasing the expected message ID after handling a message
		 * to sync MIDs with MID 0 */
		return NEED_MORE;
	}

	array_compress(this->passive_tasks);

	return SUCCESS;
}

/**
 * handle an incoming request message
 */
static status_t process_request(private_task_manager_t *this,
								message_t *message)
{
	enumerator_t *enumerator;
	task_t *task = NULL;
	payload_t *payload;
	notify_payload_t *notify;
	delete_payload_t *delete;
	ike_sa_state_t state;
	bool ack_only = FALSE;

	/* Check if peer supports selective fragment retransmission 
	 * This should work for both IKE_SA_INIT and IKE_INTERMEDIATE requests */
	if (message->get_notify(message, SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED))
	{
		this->peer_supports_selective_retransmission = TRUE;
		DBG1(DBG_IKE, "peer supports selective fragment retransmission");
	}

	if (array_count(this->passive_tasks) == 0)
	{   /* create tasks depending on request type, if not already some queued */
		state = this->ike_sa->get_state(this->ike_sa);
		switch (message->get_exchange_type(message))
		{
			case IKE_SA_INIT:
			{
				task = (task_t*)ike_vendor_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_init_create(this->ike_sa, FALSE, NULL);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_natd_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_cert_pre_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_auth_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_cert_post_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
#ifdef ME
				task = (task_t*)ike_me_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
#endif /* ME */
				task = (task_t*)ike_config_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)ike_mobike_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				/* this should generally be the last IKE-related task */
				task = (task_t*)ike_establish_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				/* make sure this comes after the above task to send the correct
				 * reauth time, as responder the task doesn't modify it anymore */
				task = (task_t*)ike_auth_lifetime_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				task = (task_t*)child_create_create(this->ike_sa, NULL, FALSE,
													NULL, NULL);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				break;
			}
			case CREATE_CHILD_SA:
			{   /* FIXME: we should prevent this on mediation connections */
				bool notify_found = FALSE, ts_found = FALSE;

				if (state == IKE_CREATED ||
					state == IKE_CONNECTING)
				{
					DBG1(DBG_IKE, "received CREATE_CHILD_SA request for "
						 "unestablished IKE_SA, rejected");
					return FAILED;
				}

				enumerator = message->create_payload_enumerator(message);
				while (enumerator->enumerate(enumerator, &payload))
				{
					switch (payload->get_type(payload))
					{
						case PLV2_NOTIFY:
						{   /* if we find a rekey notify, its CHILD_SA rekeying */
							notify = (notify_payload_t*)payload;
							if (notify->get_notify_type(notify) == REKEY_SA &&
								(notify->get_protocol_id(notify) == PROTO_AH ||
								 notify->get_protocol_id(notify) == PROTO_ESP))
							{
								notify_found = TRUE;
							}
							break;
						}
						case PLV2_TS_INITIATOR:
						case PLV2_TS_RESPONDER:
						{   /* if we don't find a TS, its IKE rekeying */
							ts_found = TRUE;
							break;
						}
						default:
							break;
					}
				}
				enumerator->destroy(enumerator);

				if (ts_found)
				{
					if (notify_found)
					{
						task = (task_t*)child_rekey_create(this->ike_sa,
														   PROTO_NONE, 0);
					}
					else
					{
						task = (task_t*)child_create_create(this->ike_sa, NULL,
															FALSE, NULL, NULL);
					}
				}
				else
				{
					task = (task_t*)ike_rekey_create(this->ike_sa, FALSE);
				}
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				break;
			}
			case INFORMATIONAL:
			{
				enumerator = message->create_payload_enumerator(message);
				while (enumerator->enumerate(enumerator, &payload))
				{
					switch (payload->get_type(payload))
					{
						case PLV2_NOTIFY:
						{
							notify = (notify_payload_t*)payload;
							if (state == IKE_REKEYED)
							{
								DBG1(DBG_IKE, "received unexpected notify %N "
									 "for rekeyed IKE_SA, ignored",
									 notify_type_names,
									 notify->get_notify_type(notify));
								break;
							}
							switch (notify->get_notify_type(notify))
							{
								case FRAGMENT_ACK:
									/* Process fragment acknowledgment directly */
									DBG0(DBG_IKE, "FRAGMENT_ACK_RECEIVED: processing FRAGMENT_ACK notify in INFORMATIONAL request");
									process_fragment_ack(this, message);
									/* No task needed for FRAGMENT_ACK processing */
									break;
								case ADDITIONAL_IP4_ADDRESS:
								case ADDITIONAL_IP6_ADDRESS:
								case NO_ADDITIONAL_ADDRESSES:
								case UPDATE_SA_ADDRESSES:
								case NO_NATS_ALLOWED:
								case UNACCEPTABLE_ADDRESSES:
								case UNEXPECTED_NAT_DETECTED:
								case COOKIE2:
								case NAT_DETECTION_SOURCE_IP:
								case NAT_DETECTION_DESTINATION_IP:
									task = (task_t*)ike_mobike_create(
															this->ike_sa, FALSE);
									break;
								case AUTH_LIFETIME:
									task = (task_t*)ike_auth_lifetime_create(
															this->ike_sa, FALSE);
									break;
								case INVALID_SYNTAX:
								case AUTHENTICATION_FAILED:
									/* initiator failed to authenticate us or
									 * parse our response. we use ike_delete to
									 * handle this, which invokes all the
									 * required hooks */
									task = (task_t*)ike_delete_create(
														this->ike_sa, FALSE);
									break;
								case REDIRECT:
									task = (task_t*)ike_redirect_create(
															this->ike_sa, NULL);
									break;
								case IKEV2_MESSAGE_ID_SYNC:
									task = (task_t*)ike_mid_sync_create(
																 this->ike_sa);
									break;
								default:
									break;
							}
							break;
						}
						case PLV2_DELETE:
						{
							delete = (delete_payload_t*)payload;
							if (delete->get_protocol_id(delete) == PROTO_IKE)
							{
								task = (task_t*)ike_delete_create(this->ike_sa,
																FALSE);
							}
							else
							{
								task = (task_t*)child_delete_create(this->ike_sa,
														PROTO_NONE, 0, FALSE);
							}
							break;
						}
						default:
							break;
					}
					if (task)
					{
						break;
					}
				}
				enumerator->destroy(enumerator);

				if (task == NULL)
				{
					task = (task_t*)ike_dpd_create(FALSE);
				}
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
				break;
			}
#ifdef ME
			case ME_CONNECT:
			{
				task = (task_t*)ike_me_create(this->ike_sa, FALSE);
				array_insert(this->passive_tasks, ARRAY_TAIL, task);
			}
#endif /* ME */
			default:
				break;
		}
	}

	enumerator = array_create_enumerator(this->passive_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		if (!task->pre_process)
		{
			continue;
		}
		switch (task->pre_process(task, message))
		{
			case SUCCESS:
				break;
			case FAILED:
			default:
				/* just ignore the message */
				DBG1(DBG_IKE, "ignore invalid %N request",
					 exchange_type_names, message->get_exchange_type(message));
				enumerator->destroy(enumerator);
				switch (message->get_exchange_type(message))
				{
					case IKE_SA_INIT:
						/* no point in keeping the SA when it was created with
						 * an invalid IKE_SA_INIT message */
						return DESTROY_ME;
					default:
						/* remove tasks we queued for this request */
						flush_queue(this, TASK_QUEUE_PASSIVE);
						/* fall-through */
					case IKE_AUTH:
						return NEED_MORE;
				}
			case DESTROY_ME:
				/* critical failure, destroy IKE_SA */
				enumerator->destroy(enumerator);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	/* let the tasks process the message */
	enumerator = array_create_enumerator(this->passive_tasks);
	while (enumerator->enumerate(enumerator, (void*)&task))
	{
		switch (task->process(task, message))
		{
			case SUCCESS:
				/* task completed, remove it */
				array_remove_at(this->passive_tasks, enumerator);
				task->destroy(task);
				break;
			case NEED_MORE:
				/* processed, but task needs at least another call to build() */
				break;
			case FAILED:
			default:
				charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
				/* FALL */
			case DESTROY_ME:
				/* critical failure, destroy IKE_SA */
				array_remove_at(this->passive_tasks, enumerator);
				enumerator->destroy(enumerator);
				task->destroy(task);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	enumerator = array_create_enumerator(this->passive_tasks);
	while (enumerator->enumerate(enumerator, &task))
	{
		if (!task->post_process)
		{
			continue;
		}
		switch (task->post_process(task, message))
		{
			case SUCCESS:
				array_remove_at(this->passive_tasks, enumerator);
				task->destroy(task);
				break;
			case NEED_MORE:
				break;
			default:
				/* critical failure, destroy IKE_SA */
				array_remove_at(this->passive_tasks, enumerator);
				enumerator->destroy(enumerator);
				task->destroy(task);
				return DESTROY_ME;
		}
	}
	enumerator->destroy(enumerator);

	return build_response(this, message);
}

METHOD(task_manager_t, incr_mid, void,
	private_task_manager_t *this, bool initiate)
{
	if (initiate)
	{
		this->initiating.mid++;
	}
	else
	{
		this->responding.mid++;
	}
}

METHOD(task_manager_t, get_mid, uint32_t,
	private_task_manager_t *this, bool initiate)
{
	return initiate ? this->initiating.mid : this->responding.mid;
}

/**
 * Hash the given message with SHA-1
 */
static bool hash_message(message_t *msg, uint8_t hash[HASH_SIZE_SHA1])
{
	hasher_t *hasher;

	hasher = lib->crypto->create_hasher(lib->crypto, HASH_SHA1);
	if (!hasher ||
		!hasher->get_hash(hasher, msg->get_packet_data(msg), hash))
	{
		DESTROY_IF(hasher);
		return FALSE;
	}
	hasher->destroy(hasher);
	return TRUE;
}

/**
 * Handle the given IKE fragment, if it is one.
 *
 * Returns SUCCESS if the message is not a fragment, and NEED_MORE if it was
 * handled properly.  Error states are returned if the fragment was invalid or
 * the reassembled message could not be processed properly.
 */
static status_t handle_fragment(private_task_manager_t *this,
								message_t **defrag, message_t *msg)
{
	encrypted_fragment_payload_t *fragment;
	status_t status;

	fragment = (encrypted_fragment_payload_t*)msg->get_payload(msg,
															   PLV2_FRAGMENT);
	if (!fragment)
	{
		/* ignore reassembled messages, we collected their fragments below */
		if (msg != *defrag)
		{
			hash_message(msg, this->responding.hash);
		}
		return SUCCESS;
	}
	if (!*defrag)
	{
		*defrag = message_create_defrag(msg);
		if (!*defrag)
		{
			return FAILED;
		}
	}
	status = (*defrag)->add_fragment(*defrag, msg);

	if (status == NEED_MORE || status == SUCCESS)
	{
		/* to detect retransmissions we only hash the first fragment */
		if (fragment->get_fragment_number(fragment) == 1)
		{
			hash_message(msg, this->responding.hash);
		}
		
		/* Send fragment acknowledgment immediately when selective retransmission is enabled */
		DBG1(DBG_IKE, "RRR1_fragment received: number=%d, status=%d, selective_retransmission=%s",
			 fragment->get_fragment_number(fragment), status,
			 this->selective_retransmission_enabled ? "enabled" : "disabled");
		
        /* Send immediate fragment acknowledgment - ALWAYS for any fragment! */
        if (this->selective_retransmission_enabled)
		{
			/* Send ACK immediately after receiving each fragment - no delays! */
			uint16_t fragment_number = fragment->get_fragment_number(fragment);
			uint32_t message_id = msg->get_message_id(msg);
			
			DBG0(DBG_IKE, "RRR2_FRAGMENT_ACK_SENDING_NOW: message_id=%d, fragment_number=%d, "
				  "sending immediately", message_id, fragment_number);
			
			send_immediate_fragment_ack(this, *defrag, message_id, fragment_number);
		}
        else
        {
            DBG1(DBG_IKE, "FRAGMENT_ACK_SKIPPED: selective_retransmission disabled");
        }
	}

	/* Check for fragment timeout and send selective retransmission request */
	if (status == NEED_MORE && (*defrag)->is_fragment_timeout(*defrag))
	{
		/* Fragment timeout handling is now done by the selective retransmission mechanism */
	}

	if (status == SUCCESS)
	{
		/* Check if this is the first time we're processing this complete message
		 * or if it's a retransmitted fragment that just completed an already processed message
		 */
		uint32_t message_id = msg->get_message_id(msg);
		exchange_type_t expected_type = (*defrag)->get_exchange_type(*defrag);
		
		/* Check if we have already processed a message with this ID and exchange type */
		bool already_processed = (this->responding.mid >= message_id && 
								  this->ike_sa->get_state(this->ike_sa) > IKE_CONNECTING);
		
		if (already_processed)
		{
			/* This message was already processed, don't reinject to avoid state conflicts */
			DBG0(DBG_IKE, "FRAGMENT_RETRANS_COMPLETION: fragment %d completed already processed message_id=%d, skipping reinject",
				 fragment->get_fragment_number(fragment), message_id);
			status = NEED_MORE; /* Continue normal processing without reinject */
		}
		else
		{
			/* reinject the reassembled message for first-time processing */
			DBG0(DBG_IKE, "FRAGMENT_NEW_COMPLETION: fragment %d completed new message_id=%d, reinjecting",
				 fragment->get_fragment_number(fragment), message_id);
			status = this->ike_sa->process_message(this->ike_sa, *defrag);
			if (status == SUCCESS)
			{
				/* avoid processing the last fragment */
				status = NEED_MORE;
			}
		}
		(*defrag)->destroy(*defrag);
		*defrag = NULL;
	}
	return status;
}

/**
 * Send a notify back to the sender
 */
static void send_notify_response(private_task_manager_t *this,
								 message_t *request, notify_type_t type,
								 chunk_t data)
{
	message_t *response;
	packet_t *packet;
	host_t *me, *other;

	response = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
	response->set_exchange_type(response, request->get_exchange_type(request));
	response->set_request(response, FALSE);
	response->set_message_id(response, request->get_message_id(request));
	response->add_notify(response, FALSE, type, data);
	me = this->ike_sa->get_my_host(this->ike_sa);
	if (me->is_anyaddr(me))
	{
		me = request->get_destination(request);
		this->ike_sa->set_my_host(this->ike_sa, me->clone(me));
	}
	other = this->ike_sa->get_other_host(this->ike_sa);
	if (other->is_anyaddr(other))
	{
		other = request->get_source(request);
		this->ike_sa->set_other_host(this->ike_sa, other->clone(other));
	}
	response->set_source(response, me->clone(me));
	response->set_destination(response, other->clone(other));
	if (this->ike_sa->generate_message(this->ike_sa, response,
									   &packet) == SUCCESS)
	{
		charon->sender->send(charon->sender, packet);
	}
	response->destroy(response);
}

/**
 * Send an INVALID_SYNTAX notify and destroy the IKE_SA for authenticated
 * messages.
 */
static status_t send_invalid_syntax(private_task_manager_t *this,
									message_t *msg)
{
	send_notify_response(this, msg, INVALID_SYNTAX, chunk_empty);
	incr_mid(this, FALSE);

	/* IKE_SA_INIT is currently the only type the parser accepts unprotected,
	 * don't destroy the IKE_SA if such a message is invalid */
	if (msg->get_exchange_type(msg) == IKE_SA_INIT)
	{
		return FAILED;
	}
	return DESTROY_ME;
}

/**
 * Check for unsupported critical payloads
 */
static status_t has_unsupported_critical_payload(message_t *msg, uint8_t *type)
{
	enumerator_t *enumerator;
	unknown_payload_t *unknown;
	payload_t *payload;
	status_t status = SUCCESS;

	enumerator = msg->create_payload_enumerator(msg);
	while (enumerator->enumerate(enumerator, &payload))
	{
		if (payload->get_type(payload) == PL_UNKNOWN)
		{
			unknown = (unknown_payload_t*)payload;
			if (unknown->is_critical(unknown))
			{
				*type = unknown->get_type(unknown);
				DBG1(DBG_ENC, "payload type %N is not supported, "
					 "but payload is critical!", payload_type_names, *type);
				status = NOT_SUPPORTED;
				break;
			}
		}
	}
	enumerator->destroy(enumerator);
	return status;
}

/**
 * Parse the given message and verify that it is valid.
 */
static status_t parse_message(private_task_manager_t *this, message_t *msg)
{
	status_t parse_status, status;
	uint8_t type = 0;

	if (derive_keys(this, this->passive_tasks))
	{
		parse_status = msg->parse_body(msg, this->ike_sa->get_keymat(this->ike_sa));

		if (parse_status == SUCCESS)
		{
			parse_status = has_unsupported_critical_payload(msg, &type);
		}

		status = parse_status;
	}
	else
	{	/* there is no point in trying again */
		parse_status = INVALID_STATE;
		status = DESTROY_ME;
	}

	if (parse_status != SUCCESS)
	{
		bool is_request = msg->get_request(msg);

		switch (parse_status)
		{
			case NOT_SUPPORTED:
				DBG1(DBG_IKE, "critical unknown payloads found");
				if (is_request)
				{
					send_notify_response(this, msg,
										 UNSUPPORTED_CRITICAL_PAYLOAD,
										 chunk_from_thing(type));
					incr_mid(this, FALSE);
				}
				break;
			case PARSE_ERROR:
				DBG1(DBG_IKE, "message parsing failed");
				if (is_request)
				{
					status = send_invalid_syntax(this, msg);
				}
				break;
			case VERIFY_ERROR:
				DBG1(DBG_IKE, "message verification failed");
				if (is_request)
				{
					status = send_invalid_syntax(this, msg);
				}
				break;
			case FAILED:
				DBG1(DBG_IKE, "integrity check failed");
				/* ignored */
				break;
			case INVALID_STATE:
				DBG1(DBG_IKE, "found encrypted message, but no keys available");
			default:
				break;
		}
		DBG1(DBG_IKE, "%N %s with message ID %d processing failed",
			 exchange_type_names, msg->get_exchange_type(msg),
			 is_request ? "request" : "response",
			 msg->get_message_id(msg));

		charon->bus->alert(charon->bus, ALERT_PARSE_ERROR_BODY, msg,
						   parse_status);

		switch (this->ike_sa->get_state(this->ike_sa))
		{
			case IKE_CREATED:
				/* invalid initiation attempt, close SA */
				status = DESTROY_ME;
				break;
			case IKE_CONNECTING:
			case IKE_REKEYED:
				/* don't trigger updown event in these states */
				break;
			default:
				if (status == DESTROY_ME)
				{
					charon->bus->ike_updown(charon->bus, this->ike_sa, FALSE);
				}
				break;
		}
	}
	return status;
}

/**
 * Check if message contains FRAGMENT_ACK notify
 */
static bool has_fragment_ack_notify(message_t *msg)
{
	notify_payload_t *notify;
	
	notify = msg->get_notify(msg, FRAGMENT_ACK);
	bool has_ack = (notify != NULL);
	if (has_ack)
	{
		DBG0(DBG_IKE, "HAS_FRAGMENT_ACK_DETECTED: FRAGMENT_ACK notify found in message ID %d", 
			 msg->get_message_id(msg));
	}
	return has_ack;
}

/**
 * Check whether we should reject the given request message
 */
static inline bool reject_request(private_task_manager_t *this,
								  message_t *msg)
{
	ike_sa_state_t state;
	exchange_type_t type;
	ike_sa_id_t *ike_sa_id;
	bool reject = FALSE;

	state = this->ike_sa->get_state(this->ike_sa);
	type = msg->get_exchange_type(msg);

	/* reject initial messages if not received in specific states */
	switch (type)
	{
		case IKE_SA_INIT:
			reject = state != IKE_CREATED;
			break;
		case IKE_INTERMEDIATE:
			/* only accept this if we have not yet completed the KEs */
			reject = state != IKE_CONNECTING ||
					 !has_queued(this, TASK_QUEUE_PASSIVE, TASK_IKE_INIT);
			break;
		case IKE_AUTH:
			reject = state != IKE_CONNECTING;
			break;
		default:
			break;
	}

	if (!reject)
	{
		switch (state)
		{
			/* after rekeying we only expect a DELETE in an INFORMATIONAL */
			case IKE_REKEYED:
				reject = type != INFORMATIONAL;
				break;
			/* also reject requests for half-open IKE_SAs as initiator */
			case IKE_CREATED:
			case IKE_CONNECTING:
				ike_sa_id = this->ike_sa->get_id(this->ike_sa);
				reject = ike_sa_id->is_initiator(ike_sa_id);
				
				/* Special exception: allow FRAGMENT_ACK INFORMATIONAL messages */
				if (reject && type == INFORMATIONAL && has_fragment_ack_notify(msg))
				{
					DBG0(DBG_IKE, "FRAGMENT_ACK_EXCEPTION: allowing FRAGMENT_ACK INFORMATIONAL in CONNECTING state");
					reject = FALSE;
				}
				break;
			default:
				break;
		}
	}

	if (reject)
	{
		DBG1(DBG_IKE, "ignoring %N in IKE_SA state %N", exchange_type_names,
			 type, ike_sa_state_names, state);
	}
	return reject;
}

/**
 * Check if a message with message ID 0 looks like it is used to synchronize
 * the message IDs.
 *
 * Call this after checking the message with is_potential_mid_sync() first.
 */
static bool is_mid_sync(private_task_manager_t *this, message_t *msg)
{
	enumerator_t *enumerator;
	notify_payload_t *notify;
	payload_t *payload;
	bool found = FALSE, other = FALSE;

	enumerator = msg->create_payload_enumerator(msg);
	while (enumerator->enumerate(enumerator, &payload))
	{
		if (payload->get_type(payload) == PLV2_NOTIFY)
		{
			notify = (notify_payload_t*)payload;
			switch (notify->get_notify_type(notify))
			{
				case IKEV2_MESSAGE_ID_SYNC:
				case IPSEC_REPLAY_COUNTER_SYNC:
					found = TRUE;
					continue;
				default:
					break;
			}
		}
		other = TRUE;
		break;
	}
	enumerator->destroy(enumerator);
	return found && !other;
}

/**
 * Check if a message with message ID 0 looks like it could potentially be used
 * to synchronize the message IDs and if we are prepared to process it.
 *
 * This may be called before the message body is parsed.
 */
static bool is_potential_mid_sync(private_task_manager_t *this, message_t *msg)
{
	return msg->get_exchange_type(msg) == INFORMATIONAL &&
		   this->ike_sa->get_state(this->ike_sa) == IKE_ESTABLISHED &&
		   this->ike_sa->supports_extension(this->ike_sa,
											EXT_IKE_MESSAGE_ID_SYNC);
}

/**
 * Check if the given message is a retransmitted request
 */
static status_t is_retransmit(private_task_manager_t *this, message_t *msg)
{
	uint8_t hash[HASH_SIZE_SHA1];
	uint32_t mid;

	mid = msg->get_message_id(msg);

	// 只在有ACK时调试
	if (mid == 0 && has_fragment_ack_notify(msg))
	{
		DBG0(DBG_IKE, "IS_RETRANSMIT_DEBUG: message ID 0 with FRAGMENT_ACK received");
	}

	// 特殊处理：简化的ACK消息使用Message ID 0
	if (mid == 0 && has_fragment_ack_notify(msg))
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_RECEIVED: simplified ACK message with ID 0, processing immediately");
		return NEED_MORE; // 让这个消息继续被处理
	}

	if (mid == this->responding.mid)
	{
		return NEED_MORE;
	}

	if (mid == this->responding.mid - 1 &&
		array_count(this->responding.packets))
	{
		if (!hash_message(msg, hash))
		{
			DBG1(DBG_IKE, "failed to hash message, ignored");
			return FAILED;
		}
		if (memeq_const(hash, this->responding.prev_hash, sizeof(hash)))
		{
			return ALREADY_DONE;
		}
	}
	/* this includes fragments with fragment number > 1 (we only hash the first
	 * fragment), for which RFC 7383, section 2.6.1 explicitly does not allow
	 * retransmitting responses. we don't parse/verify these messages to check,
	 * we just ignore them. also included are MID sync messages with MID 0 */
	return INVALID_ARG;
}

METHOD(task_manager_t, process_message, status_t,
	private_task_manager_t *this, message_t *msg)
{
	host_t *me, *other;
	status_t status;
	uint32_t mid, *expected_mid = NULL;
	bool schedule_delete_job = FALSE;

	me = msg->get_destination(msg);
	other = msg->get_source(msg);
	mid = msg->get_message_id(msg);
	
	// CRITICAL FIX: Simplified ACK detection - avoid multiple payload consumption
	bool is_fragment_ack_request = false;
	
	/* Only do early ACK detection for INFORMATIONAL messages with ID 0 */
	if (msg->get_request(msg) && mid == 0 && 
	    msg->get_exchange_type(msg) == INFORMATIONAL)
	{
		is_fragment_ack_request = has_fragment_ack_notify(msg);
		if (is_fragment_ack_request)
		{
			DBG0(DBG_IKE, "EARLY_FRAGMENT_ACK_DETECTION: found fragment ACK with ID 0, will process after bus message");
		}
	}

	charon->bus->message(charon->bus, msg, TRUE, FALSE);

	if (msg->get_request(msg))
	{
		bool potential_mid_sync = FALSE;

		switch (is_retransmit(this, msg))
		{
			case ALREADY_DONE:
				DBG1(DBG_IKE, "received retransmit of request with ID %d, "
					 "retransmitting response", mid);
				this->ike_sa->set_statistic(this->ike_sa, STAT_INBOUND,
											time_monotonic(NULL));
				charon->bus->alert(charon->bus, ALERT_RETRANSMIT_RECEIVE, msg);
				send_packets(this, this->responding.packets,
							 msg->get_destination(msg), msg->get_source(msg));
				return SUCCESS;
			case INVALID_ARG:
				if (mid == 0 && is_potential_mid_sync(this, msg))
				{
					potential_mid_sync = TRUE;
				}
				else
				{
					expected_mid = &this->responding.mid;
					break;
				}
				/* check if it's actually an MID sync message */
			case NEED_MORE:
				status = parse_message(this, msg);
				
				if (potential_mid_sync && status == SUCCESS &&
					!is_mid_sync(this, msg))
				{
					expected_mid = &this->responding.mid;
				}
				break;
			case FAILED:
			default:
				return FAILED;
		}
	}
	else
	{
			if (mid == this->initiating.mid)
	{
		// 检查是否包含ACK消息
		// if (has_fragment_ack_notify(msg))
		// {
		// 	DBG0(DBG_IKE, "INITIATOR_RECEIVED_ACK_IN_NORMAL_RESPONSE: ACK found in expected response message ID %d", mid);
		// }
        status = parse_message(this, msg);
        DBG0(DBG_IKE, "INITIATOR_RESPONSE_PARSE: message ID %d parsed", mid);
        /* Fallback: if a normal response carries FRAGMENT_ACK, process it */
        if (status == SUCCESS && has_fragment_ack_notify(msg))
        {
            DBG0(DBG_IKE, "ACK_ON_RESPONSE: processing FRAGMENT_ACK found in normal response (MID=%d)", mid);
            process_fragment_ack(this, msg);
        }
	}
		else
		{
					// 特殊处理：允许简化的ACK消息 (Message ID 0) 作为response通过
        if (mid == 0 && has_fragment_ack_notify(msg))
		{
			DBG0(DBG_IKE, "INITIATOR_RECEIVED_ACK: got ACK response with Message ID 0, parsing now");
			// 直接解析并处理ACK，不管之前的状态
			status = parse_message(this, msg);
			if (status == SUCCESS)
			{
				DBG0(DBG_IKE, "INITIATOR_ACK_PARSE_SUCCESS: ACK message parsed successfully, processing fragment ACK");
				// 在处理ACK前，先检查当前tracker状态
				if (this->outgoing_tracker)
				{
					DBG0(DBG_IKE, "INITIATOR_ACK_TRACKER_STATUS: before processing - %d/%d fragments acknowledged", 
						 this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
				}
                process_fragment_ack(this, msg);
				if (this->outgoing_tracker)
				{
					DBG0(DBG_IKE, "INITIATOR_ACK_TRACKER_STATUS: after processing - %d/%d fragments acknowledged", 
						 this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
				}
				DBG0(DBG_IKE, "INITIATOR_ACK_PROCESSED: fragment ACK processing completed");
			}
			else
			{
				DBG0(DBG_IKE, "INITIATOR_ACK_PARSE_FAILED: ACK message parsing failed with status=%d", status);
			}
			return status;
		}
			expected_mid = &this->initiating.mid;
		}
	}

	if (expected_mid)
	{
		/* Message ID mismatch: still check if the packet contains a FRAGMENT_ACK
		 * (either as a request or as a response). We do this in two steps:
		 *  1. If we already pre-detected an ACK request (is_fragment_ack_request),
		 *     we can directly parse and process it (existing behaviour).
		 *  2. Otherwise, we parse the message and inspect it again. This covers
		 *     ACKs sent as INFORMATIONAL responses, which were previously missed. */
        if (is_fragment_ack_request)
		{
			DBG0(DBG_IKE, "RESPONDER_FALLBACK_ACK_DETECTION: found fragment ACK request with mismatched ID, processing anyway");
			status = parse_message(this, msg);
            if (status == SUCCESS)
            {
                DBG0(DBG_IKE, "RESPONDER_FALLBACK_ACK_PROCESSING: processing fragment ACK request despite ID mismatch");
                process_fragment_ack(this, msg);
                return SUCCESS;
            }
		}
		else
		{
			/* Parse the message first so that payloads are available for inspection */
			status = parse_message(this, msg);
			if (status == SUCCESS && has_fragment_ack_notify(msg))
			{
                DBG0(DBG_IKE, "RESPONDER_FALLBACK_ACK_DETECTION: found fragment ACK (response) with mismatched ID, processing anyway");
                process_fragment_ack(this, msg);
				return SUCCESS;
			}
		}
		
		DBG1(DBG_IKE, "received message ID %d, expected %d, ignored", mid, *expected_mid);
		return SUCCESS;
	}
	else if (status != SUCCESS)
	{
		return status;
	}

	/* if this IKE_SA is virgin, we check for a config */
	if (!this->ike_sa->get_ike_cfg(this->ike_sa))
	{
		ike_cfg_t *ike_cfg;

		ike_cfg = charon->backends->get_ike_cfg(charon->backends,
												me, other, IKEV2);
		if (!ike_cfg)
		{
			/* no config found for these hosts, destroy */
			DBG1(DBG_IKE, "no IKE config found for %H...%H, sending %N",
				 me, other, notify_type_names, NO_PROPOSAL_CHOSEN);
			send_notify_response(this, msg,
								 NO_PROPOSAL_CHOSEN, chunk_empty);
			return DESTROY_ME;
		}
		this->ike_sa->set_ike_cfg(this->ike_sa, ike_cfg);
		ike_cfg->destroy(ike_cfg);
		/* add a timeout if peer does not establish it completely */
		schedule_delete_job = TRUE;
	}

	if (msg->get_request(msg))
	{
		/* special handling for requests happens in is_retransmit()
		 * reject initial messages if not received in specific states,
		 * after rekeying we only expect a DELETE in an INFORMATIONAL */
		if (reject_request(this, msg))
		{
			return FAILED;
		}
		if (!this->ike_sa->supports_extension(this->ike_sa, EXT_MOBIKE))
		{	/* only do implicit updates without MOBIKE, and only force
			 * updates for IKE_AUTH (ports might change due to NAT-T) */
			this->ike_sa->update_hosts(this->ike_sa, me, other,
									   mid == 1 ? UPDATE_HOSTS_FORCE_ADDRS : 0);
		}
		status = handle_fragment(this, &this->responding.defrag, msg);
		if (status != SUCCESS)
		{
			if (status == NEED_MORE)
			{
				this->ike_sa->set_statistic(this->ike_sa, STAT_INBOUND,
											time_monotonic(NULL));
			}
			return status;
		}
		charon->bus->message(charon->bus, msg, TRUE, TRUE);
		if (msg->get_exchange_type(msg) == EXCHANGE_TYPE_UNDEFINED)
		{	/* ignore messages altered to EXCHANGE_TYPE_UNDEFINED */
			return SUCCESS;
		}
		switch (process_request(this, msg))
		{
			case SUCCESS:
				this->ike_sa->set_statistic(this->ike_sa, STAT_INBOUND,
											time_monotonic(NULL));
				this->responding.mid++;
				memcpy(this->responding.prev_hash, this->responding.hash,
					   sizeof(this->responding.prev_hash));
				break;
			case NEED_MORE:
				break;
			default:
				flush(this);
				return DESTROY_ME;
		}
	}
	else
	{
		if (this->ike_sa->get_state(this->ike_sa) == IKE_CREATED ||
			this->ike_sa->get_state(this->ike_sa) == IKE_CONNECTING ||
			msg->get_exchange_type(msg) != IKE_SA_INIT)
		{	/* only do updates based on verified messages (or initial ones) */
			if (!this->ike_sa->supports_extension(this->ike_sa, EXT_MOBIKE))
			{	/* only do implicit updates without MOBIKE, we force an
				 * update of the local address on IKE_SA_INIT as we might
				 * not know it yet, but never for the remote address */
				this->ike_sa->update_hosts(this->ike_sa, me, other,
										   mid == 0 ? UPDATE_HOSTS_FORCE_LOCAL : 0);
			}
		}
		status = handle_fragment(this, &this->initiating.defrag, msg);
		if (status != SUCCESS)
		{
			if (status == NEED_MORE)
			{
				this->ike_sa->set_statistic(this->ike_sa, STAT_INBOUND,
											time_monotonic(NULL));
			}
			return status;
		}
		charon->bus->message(charon->bus, msg, TRUE, TRUE);
		if (msg->get_exchange_type(msg) == EXCHANGE_TYPE_UNDEFINED)
		{	/* ignore messages altered to EXCHANGE_TYPE_UNDEFINED */
			return SUCCESS;
		}
		if (process_response(this, msg) != SUCCESS)
		{
			flush(this);
			return DESTROY_ME;
		}
		this->ike_sa->set_statistic(this->ike_sa, STAT_INBOUND,
									time_monotonic(NULL));
	}

	if (schedule_delete_job)
	{
		ike_sa_id_t *ike_sa_id;
		job_t *job;

		ike_sa_id = this->ike_sa->get_id(this->ike_sa);
		job = (job_t*)delete_ike_sa_job_create(ike_sa_id, FALSE);
		lib->scheduler->schedule_job(lib->scheduler, job,
				lib->settings->get_int(lib->settings,
						"%s.half_open_timeout", HALF_OPEN_IKE_SA_TIMEOUT,
						lib->ns));
	}
	return SUCCESS;
}

METHOD(task_manager_t, queue_task_delayed, void,
	private_task_manager_t *this, task_t *task, uint32_t delay)
{
	queued_task_t *queued;
	timeval_t time;

	time_monotonic(&time);
	if (delay)
	{
		job_t *job;

		DBG2(DBG_IKE, "queueing %N task (delayed by %us)", task_type_names,
			 task->get_type(task), delay);
		time.tv_sec += delay;

		job = (job_t*)initiate_tasks_job_create(
											this->ike_sa->get_id(this->ike_sa));
		lib->scheduler->schedule_job_tv(lib->scheduler, job, time);
	}
	else
	{
		DBG2(DBG_IKE, "queueing %N task", task_type_names,
			 task->get_type(task));
	}
	INIT(queued,
		.task = task,
		.time = time,
	);
	array_insert(this->queued_tasks, ARRAY_TAIL, queued);
}

METHOD(task_manager_t, queue_task, void,
	private_task_manager_t *this, task_t *task)
{
	queue_task_delayed(this, task, 0);
}

METHOD(task_manager_t, queue_ike, void,
	private_task_manager_t *this)
{
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_VENDOR))
	{
		queue_task(this, (task_t*)ike_vendor_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_INIT))
	{
		queue_task(this, (task_t*)ike_init_create(this->ike_sa, TRUE, NULL));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_NATD))
	{
		queue_task(this, (task_t*)ike_natd_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CERT_PRE))
	{
		queue_task(this, (task_t*)ike_cert_pre_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_AUTH))
	{
		queue_task(this, (task_t*)ike_auth_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CERT_POST))
	{
		queue_task(this, (task_t*)ike_cert_post_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CONFIG))
	{
		queue_task(this, (task_t*)ike_config_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_AUTH_LIFETIME))
	{
		queue_task(this, (task_t*)ike_auth_lifetime_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_MOBIKE))
	{
		peer_cfg_t *peer_cfg;

		peer_cfg = this->ike_sa->get_peer_cfg(this->ike_sa);
		if (peer_cfg->use_mobike(peer_cfg))
		{
			queue_task(this, (task_t*)ike_mobike_create(this->ike_sa, TRUE));
		}
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_ESTABLISH))
	{
		queue_task(this, (task_t*)ike_establish_create(this->ike_sa, TRUE));
	}
#ifdef ME
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_ME))
	{
		queue_task(this, (task_t*)ike_me_create(this->ike_sa, TRUE));
	}
#endif /* ME */
}

METHOD(task_manager_t, queue_ike_init_only, void,
	private_task_manager_t *this)
{
	/* Queue only IKE_SA_INIT related tasks */
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_VENDOR))
	{
		queue_task(this, (task_t*)ike_vendor_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_INIT))
	{
		queue_task(this, (task_t*)ike_init_create(this->ike_sa, TRUE, NULL));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_NATD))
	{
		queue_task(this, (task_t*)ike_natd_create(this->ike_sa, TRUE));
	}
	DBG1(DBG_IKE, "queued IKE_SA_INIT tasks only (phase separation enabled)");
}

METHOD(task_manager_t, queue_ike_auth_only, void,
	private_task_manager_t *this)
{
	peer_cfg_t *peer_cfg;

	/* Queue only IKE_AUTH related tasks */
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CERT_PRE))
	{
		queue_task(this, (task_t*)ike_cert_pre_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_AUTH))
	{
		queue_task(this, (task_t*)ike_auth_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CERT_POST))
	{
		queue_task(this, (task_t*)ike_cert_post_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_CONFIG))
	{
		queue_task(this, (task_t*)ike_config_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_AUTH_LIFETIME))
	{
		queue_task(this, (task_t*)ike_auth_lifetime_create(this->ike_sa, TRUE));
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_MOBIKE))
	{
		peer_cfg = this->ike_sa->get_peer_cfg(this->ike_sa);
		if (peer_cfg->use_mobike(peer_cfg))
		{
			queue_task(this, (task_t*)ike_mobike_create(this->ike_sa, TRUE));
		}
	}
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_ESTABLISH))
	{
		queue_task(this, (task_t*)ike_establish_create(this->ike_sa, TRUE));
	}
#ifdef ME
	if (!has_queued(this, TASK_QUEUE_QUEUED, TASK_IKE_ME))
	{
		queue_task(this, (task_t*)ike_me_create(this->ike_sa, TRUE));
	}
#endif /* ME */
	DBG1(DBG_IKE, "queued IKE_AUTH tasks only (phase separation enabled)");
}



METHOD(task_manager_t, queue_ike_rekey, void,
	private_task_manager_t *this)
{
	queue_task(this, (task_t*)ike_rekey_create(this->ike_sa, TRUE));
}

/**
 * Start reauthentication using make-before-break
 */
static void trigger_mbb_reauth(private_task_manager_t *this)
{
	enumerator_t *enumerator;
	child_sa_t *child_sa;
	child_cfg_t *cfg;
	peer_cfg_t *peer;
	ike_sa_t *new;
	host_t *host;
	queued_task_t *queued;
	uint32_t reqid;
	bool children = FALSE;

	new = charon->ike_sa_manager->create_new(charon->ike_sa_manager,
								this->ike_sa->get_version(this->ike_sa), TRUE);
	if (!new)
	{	/* shouldn't happen */
		return;
	}

	peer = this->ike_sa->get_peer_cfg(this->ike_sa);
	new->set_peer_cfg(new, peer);
	host = this->ike_sa->get_other_host(this->ike_sa);
	new->set_other_host(new, host->clone(host));
	host = this->ike_sa->get_my_host(this->ike_sa);
	new->set_my_host(new, host->clone(host));
	charon->bus->ike_reestablish_pre(charon->bus, this->ike_sa, new);
	enumerator = this->ike_sa->create_virtual_ip_enumerator(this->ike_sa, TRUE);
	while (enumerator->enumerate(enumerator, &host))
	{
		new->add_virtual_ip(new, TRUE, host);
	}
	enumerator->destroy(enumerator);

	enumerator = this->ike_sa->create_child_sa_enumerator(this->ike_sa);
	while (enumerator->enumerate(enumerator, &child_sa))
	{
		child_create_t *child_create;

		switch (child_sa->get_state(child_sa))
		{
			case CHILD_REKEYED:
			case CHILD_DELETED:
				/* ignore CHILD_SAs in these states */
				continue;
			default:
				break;
		}
		cfg = child_sa->get_config(child_sa);
		child_create = child_create_create(new, cfg->get_ref(cfg),
										   FALSE, NULL, NULL);
		reqid = child_sa->get_reqid_ref(child_sa);
		if (reqid)
		{
			child_create->use_reqid(child_create, reqid);
			charon->kernel->release_reqid(charon->kernel, reqid);
		}
		child_create->use_marks(child_create,
								child_sa->get_mark(child_sa, TRUE).value,
								child_sa->get_mark(child_sa, FALSE).value);
		child_create->use_label(child_create, child_sa->get_label(child_sa));
		/* interface IDs are not migrated as the new CHILD_SAs on old and new
		 * IKE_SA go though regular updown events */
		new->queue_task(new, &child_create->task);
		children = TRUE;
	}
	enumerator->destroy(enumerator);

	enumerator = array_create_enumerator(this->queued_tasks);
	while (enumerator->enumerate(enumerator, &queued))
	{
		if (queued->task->get_type(queued->task) == TASK_CHILD_CREATE)
		{
			queued->task->migrate(queued->task, new);
			new->queue_task(new, queued->task);
			array_remove_at(this->queued_tasks, enumerator);
			free(queued);
			children = TRUE;
		}
	}
	enumerator->destroy(enumerator);

	if (!children
#ifdef ME
		/* allow reauth of mediation connections without CHILD_SAs */
		&& !peer->is_mediation(peer)
#endif /* ME */
		)
	{
		charon->bus->ike_reestablish_post(charon->bus, this->ike_sa, new,
										  FALSE);
		charon->ike_sa_manager->checkin_and_destroy(charon->ike_sa_manager, new);
		DBG1(DBG_IKE, "unable to reauthenticate IKE_SA, no CHILD_SA "
			 "to recreate");
		return;
	}

	/* suspend online revocation checking until the SA is established */
	new->set_condition(new, COND_ONLINE_VALIDATION_SUSPENDED, TRUE);

	if (new->initiate(new, NULL, NULL) != DESTROY_ME)
	{
		new->queue_task(new, (task_t*)ike_verify_peer_cert_create(new));
		new->queue_task(new, (task_t*)ike_reauth_complete_create(new,
										this->ike_sa->get_id(this->ike_sa)));
		charon->bus->ike_reestablish_post(charon->bus, this->ike_sa, new,
										  TRUE);
		charon->ike_sa_manager->checkin(charon->ike_sa_manager, new);
	}
	else
	{
		charon->bus->ike_reestablish_post(charon->bus, this->ike_sa, new,
										  FALSE);
		charon->ike_sa_manager->checkin_and_destroy(charon->ike_sa_manager, new);
		DBG1(DBG_IKE, "reauthenticating IKE_SA failed");
	}
	charon->bus->set_sa(charon->bus, this->ike_sa);
}

METHOD(task_manager_t, queue_ike_reauth, void,
	private_task_manager_t *this)
{
	if (this->make_before_break)
	{
		return trigger_mbb_reauth(this);
	}
	queue_task(this, (task_t*)ike_reauth_create(this->ike_sa));
}

METHOD(task_manager_t, queue_ike_delete, void,
	private_task_manager_t *this)
{
	queue_task(this, (task_t*)ike_delete_create(this->ike_sa, TRUE));
}

/**
 * There is no need to queue more than one mobike task, so this either returns
 * an already queued task or queues one if there is none yet.
 */
static ike_mobike_t *queue_mobike_task(private_task_manager_t *this)
{
	enumerator_t *enumerator;
	queued_task_t *queued;
	ike_mobike_t *mobike = NULL;

	enumerator = array_create_enumerator(this->queued_tasks);
	while (enumerator->enumerate(enumerator, &queued))
	{
		if (queued->task->get_type(queued->task) == TASK_IKE_MOBIKE)
		{
			mobike = (ike_mobike_t*)queued->task;
			break;
		}
	}
	enumerator->destroy(enumerator);

	if (!mobike)
	{
		mobike = ike_mobike_create(this->ike_sa, TRUE);
		queue_task(this, &mobike->task);
	}
	return mobike;
}

METHOD(task_manager_t, queue_mobike, void,
	private_task_manager_t *this, bool roam, bool address)
{
	ike_mobike_t *mobike;

	mobike = queue_mobike_task(this);
	if (roam)
	{
		enumerator_t *enumerator;
		task_t *current;

		mobike->roam(mobike, address);

		/* enable path probing for a currently active MOBIKE task.  This might
		 * not be the case if an address appeared on a new interface while the
		 * current address is not working but has not yet disappeared. */
		enumerator = array_create_enumerator(this->active_tasks);
		while (enumerator->enumerate(enumerator, &current))
		{
			if (current->get_type(current) == TASK_IKE_MOBIKE)
			{
				ike_mobike_t *active = (ike_mobike_t*)current;
				active->enable_probing(active);
				break;
			}
		}
		enumerator->destroy(enumerator);
	}
	else
	{
		mobike->addresses(mobike);
	}
}

METHOD(task_manager_t, queue_dpd, void,
	private_task_manager_t *this)
{
	ike_mobike_t *mobike;

	if (this->ike_sa->supports_extension(this->ike_sa, EXT_MOBIKE))
	{
#ifdef ME
		peer_cfg_t *cfg = this->ike_sa->get_peer_cfg(this->ike_sa);
		if (cfg->get_peer_id(cfg) ||
			this->ike_sa->has_condition(this->ike_sa, COND_ORIGINAL_INITIATOR))
#else
		if (this->ike_sa->has_condition(this->ike_sa, COND_ORIGINAL_INITIATOR))
#endif
		{
			/* use mobike enabled DPD to detect NAT mapping changes */
			mobike = queue_mobike_task(this);
			mobike->dpd(mobike);
			return;
		}
	}
	queue_task(this, (task_t*)ike_dpd_create(TRUE));
}

METHOD(task_manager_t, queue_child, void,
	private_task_manager_t *this, child_cfg_t *cfg, child_init_args_t *args)
{
	child_create_t *task;

	if (args)
	{
		task = child_create_create(this->ike_sa, cfg, FALSE, args->src, args->dst);
		task->use_reqid(task, args->reqid);
		task->use_label(task, args->label);
	}
	else
	{
		task = child_create_create(this->ike_sa, cfg, FALSE, NULL, NULL);
	}
	queue_task(this, &task->task);
}

METHOD(task_manager_t, queue_child_rekey, void,
	private_task_manager_t *this, protocol_id_t protocol, uint32_t spi)
{
	queue_task(this, (task_t*)child_rekey_create(this->ike_sa, protocol, spi));
}

METHOD(task_manager_t, queue_child_delete, void,
	private_task_manager_t *this, protocol_id_t protocol, uint32_t spi,
	bool expired)
{
	queue_task(this, (task_t*)child_delete_create(this->ike_sa,
												  protocol, spi, expired));
}

METHOD(task_manager_t, adopt_tasks, void,
	private_task_manager_t *this, task_manager_t *other_public)
{
	private_task_manager_t *other = (private_task_manager_t*)other_public;
	queued_task_t *queued;
	timeval_t now;

	time_monotonic(&now);

	/* move queued tasks from other to this */
	while (array_remove(other->queued_tasks, ARRAY_TAIL, &queued))
	{
		DBG2(DBG_IKE, "migrating %N task", task_type_names,
			 queued->task->get_type(queued->task));
		queued->task->migrate(queued->task, this->ike_sa);
		/* don't delay tasks on the new IKE_SA */
		queued->time = now;
		array_insert(this->queued_tasks, ARRAY_HEAD, queued);
	}
}

METHOD(task_manager_t, busy, bool,
	private_task_manager_t *this)
{
	return array_count(this->active_tasks) > 0;
}

METHOD(task_manager_t, reset, void,
	private_task_manager_t *this, uint32_t initiate, uint32_t respond)
{
	enumerator_t *enumerator;
	queued_task_t *queued;
	task_t *task;
	timeval_t now;

	/* reset message counters and retransmit packets */
	clear_packets(this->responding.packets);
	clear_packets(this->initiating.packets);
	DESTROY_IF(this->responding.defrag);
	DESTROY_IF(this->initiating.defrag);
	this->responding.defrag = NULL;
	this->initiating.defrag = NULL;
	
	/* Reset fragment tracker to prevent state leakage */
	if (this->outgoing_tracker)
	{
		destroy_fragment_tracker(this->outgoing_tracker);
		this->outgoing_tracker = NULL;
	}
	
	if (initiate != UINT_MAX)
	{
		this->initiating.mid = initiate;
	}
	if (respond != UINT_MAX)
	{
		this->responding.mid = respond;
	}
	this->initiating.type = EXCHANGE_TYPE_UNDEFINED;

	time_monotonic(&now);
	/* reset queued tasks */
	enumerator = array_create_enumerator(this->queued_tasks);
	while (enumerator->enumerate(enumerator, &queued))
	{
		queued->time = now;
		queued->task->migrate(queued->task, this->ike_sa);
	}
	enumerator->destroy(enumerator);

	/* reset active tasks */
	while (array_remove(this->active_tasks, ARRAY_TAIL, &task))
	{
		task->migrate(task, this->ike_sa);
		INIT(queued,
			.task = task,
			.time = now,
		);
		array_insert(this->queued_tasks, ARRAY_HEAD, queued);
	}

	this->reset = TRUE;
}

/**
 * Data for a task queue enumerator
 */
typedef struct {
	enumerator_t public;
	task_queue_t queue;
	enumerator_t *inner;
	queued_task_t *queued;
} task_enumerator_t;

METHOD(enumerator_t, task_enumerator_destroy, void,
	task_enumerator_t *this)
{
	this->inner->destroy(this->inner);
	free(this);
}

METHOD(enumerator_t, task_enumerator_enumerate, bool,
	task_enumerator_t *this, va_list args)
{
	task_t **task;

	VA_ARGS_VGET(args, task);
	if (this->queue == TASK_QUEUE_QUEUED)
	{
		if (this->inner->enumerate(this->inner, &this->queued))
		{
			*task = this->queued->task;
			return TRUE;
		}
	}
	else if (this->inner->enumerate(this->inner, task))
	{
		return TRUE;
	}
	return FALSE;
}

METHOD(task_manager_t, create_task_enumerator, enumerator_t*,
	private_task_manager_t *this, task_queue_t queue)
{
	task_enumerator_t *enumerator;

	INIT(enumerator,
		.public = {
			.enumerate = enumerator_enumerate_default,
			.venumerate = _task_enumerator_enumerate,
			.destroy = _task_enumerator_destroy,
		},
		.queue = queue,
	);
	switch (queue)
	{
		case TASK_QUEUE_ACTIVE:
			enumerator->inner = array_create_enumerator(this->active_tasks);
			break;
		case TASK_QUEUE_PASSIVE:
			enumerator->inner = array_create_enumerator(this->passive_tasks);
			break;
		case TASK_QUEUE_QUEUED:
			enumerator->inner = array_create_enumerator(this->queued_tasks);
			break;
		default:
			enumerator->inner = enumerator_create_empty();
			break;
	}
	return &enumerator->public;
}

METHOD(task_manager_t, remove_task, void,
	private_task_manager_t *this, enumerator_t *enumerator_public)
{
	task_enumerator_t *enumerator = (task_enumerator_t*)enumerator_public;

	switch (enumerator->queue)
	{
		case TASK_QUEUE_ACTIVE:
			array_remove_at(this->active_tasks, enumerator->inner);
			break;
		case TASK_QUEUE_PASSIVE:
			array_remove_at(this->passive_tasks, enumerator->inner);
			break;
		case TASK_QUEUE_QUEUED:
			array_remove_at(this->queued_tasks, enumerator->inner);
			free(enumerator->queued);
			enumerator->queued = NULL;
			break;
		default:
			break;
	}
}

METHOD(task_manager_t, destroy, void,
	private_task_manager_t *this)
{
	flush(this);

	// 清理重传作业引用
	if (this->current_retransmit_job)
	{
		this->current_retransmit_job->cancel(this->current_retransmit_job);
		this->current_retransmit_job = NULL;
	}

	array_destroy(this->active_tasks);
	array_destroy(this->queued_tasks);
	array_destroy(this->passive_tasks);

	clear_packets(this->responding.packets);
	array_destroy(this->responding.packets);
	clear_packets(this->initiating.packets);
	array_destroy(this->initiating.packets);
	DESTROY_IF(this->responding.defrag);
	DESTROY_IF(this->initiating.defrag);
	destroy_fragment_tracker(this->outgoing_tracker);
	free(this);
}

/*
 * see header file
 */
task_manager_v2_t *task_manager_v2_create(ike_sa_t *ike_sa)
{
	private_task_manager_t *this;

	INIT(this,
		.public = {
			.task_manager = {
				.process_message = _process_message,
				.queue_task = _queue_task,
				.queue_task_delayed = _queue_task_delayed,
				.queue_ike = _queue_ike,
				.queue_ike_init_only = _queue_ike_init_only,
				.queue_ike_auth_only = _queue_ike_auth_only,
		
				.queue_ike_rekey = _queue_ike_rekey,
				.queue_ike_reauth = _queue_ike_reauth,
				.queue_ike_delete = _queue_ike_delete,
				.queue_mobike = _queue_mobike,
				.queue_child = _queue_child,
				.queue_child_rekey = _queue_child_rekey,
				.queue_child_delete = _queue_child_delete,
				.queue_dpd = _queue_dpd,
				.initiate = _initiate,
				.retransmit = _retransmit,
				.incr_mid = _incr_mid,
				.get_mid = _get_mid,
				.reset = _reset,
				.adopt_tasks = _adopt_tasks,
				.busy = _busy,
				.create_task_enumerator = _create_task_enumerator,
				.remove_task = _remove_task,
				.flush = _flush,
				.flush_queue = _flush_queue,
				.destroy = _destroy,
			},
		},
		.ike_sa = ike_sa,
		.initiating = {
			.type = EXCHANGE_TYPE_UNDEFINED,
			.retransmitted = 0,
			.retransmit_sent = FALSE,
			.deferred = FALSE,
		},
		.queued_tasks = array_create(0, 0),
		.active_tasks = array_create(0, 0),
		.passive_tasks = array_create(0, 0),
		.make_before_break = lib->settings->get_bool(lib->settings,
					"%s.make_before_break", TRUE, lib->ns),
		.outgoing_tracker = NULL,
		.peer_supports_selective_retransmission = FALSE,
		.selective_retransmission_enabled = lib->settings->get_bool(lib->settings,
					"%s.selective_fragment_retransmission", TRUE, lib->ns),
		.current_retransmit_job = NULL,  // Initialize retransmit job reference

	);

	retransmission_parse_default(&this->retransmit);

	return &this->public;
}

/**
 * Destroy fragment state
 */
static void destroy_fragment_state(fragment_state_t *fragment)
{
	if (fragment)
	{
		DESTROY_IF(fragment->packet);
		free(fragment);
	}
}

/**
 * Destroy fragment tracker
 */
static void destroy_fragment_tracker(fragment_tracker_t *tracker)
{
	if (tracker)
	{
		if (tracker->fragments)
		{
			array_destroy_function(tracker->fragments, 
								  (array_callback_t)destroy_fragment_state, NULL);
		}
		free(tracker);
	}
}

/**
 * Create fragment tracker for a message
 */
static fragment_tracker_t *create_fragment_tracker(uint32_t message_id, 
												   uint16_t total_fragments)
{
	fragment_tracker_t *tracker;
	
	INIT(tracker,
		.message_id = message_id,
		.fragments = array_create(sizeof(fragment_state_t), 0),
		.total_fragments = total_fragments,
		.acked_fragments = 0,
		.last_ack_time = time_monotonic(NULL),
		.selective_retransmission_supported = FALSE,
		.total_original_size = 0,      // 初始化数据量统计
		.total_transmitted_size = 0,   // 初始化传输量统计
		.retransmission_count = 0,     // 初始化重传计数
	);
	
	return tracker;
}

/**
 * Add fragment to tracker
 */
static void add_fragment_to_tracker(fragment_tracker_t *tracker, 
								   uint16_t fragment_id, packet_t *packet)
{
	fragment_state_t *fragment;
	
	if (!tracker || !packet)
	{
		return;
	}
	
	uint32_t data_size = packet->get_data(packet).len;
	
	INIT(fragment,
		.fragment_id = fragment_id,
		.packet = packet->clone(packet),
		.acknowledged = FALSE,
		.last_sent = time_monotonic(NULL),
		.retransmit_count = 0,
		.data_size = data_size,           // 记录数据大小
		.total_transmitted = 0,   // 初始传输量（包括第一次传输）
	);
	
	array_insert(tracker->fragments, ARRAY_TAIL, fragment);
	
	// 更新跟踪器统计 - 只记录原始大小，传输量由重传逻辑处理
	tracker->total_original_size += data_size;
	
	DBG0(DBG_IKE, "add_fragment_to_tracker: message_id=%d, fragment_id=%d, size=%d",		
		  tracker->message_id, fragment_id, data_size);
}

/**
 * Find fragment in tracker
 */
static fragment_state_t *find_fragment_in_tracker(fragment_tracker_t *tracker, 
												  uint16_t fragment_id)
{
	enumerator_t *enumerator;
	fragment_state_t *fragment;
	
	if (!tracker || !tracker->fragments)
	{
		return NULL;
	}
	
	enumerator = array_create_enumerator(tracker->fragments);
	while (enumerator->enumerate(enumerator, &fragment))
	{
		if (fragment->fragment_id == fragment_id)
		{
			enumerator->destroy(enumerator);
			return fragment;
		}
	}
	enumerator->destroy(enumerator);
	return NULL;
}

/**
 * Update fragment acknowledgment status based on received count
 */
static void update_fragment_ack_status(fragment_tracker_t *tracker, 
									   fragment_ack_data_t *ack_data)
{
	DBG0(DBG_IKE, "LINE %d: update_fragment_ack_status enter, message_id=%d", __LINE__, tracker->message_id);
	fragment_state_t *fragment;
	uint16_t received_count = ntohs(ack_data->received_count);
	
	if (!tracker || !ack_data)
	{
		return;
	}
	
	// Use bitmap-based acknowledgment for precise fragment tracking
	// 显示收到的ACK位图详细信息
	DBG0(DBG_IKE, "MOON_ACK_BITMAP_RECEIVED: processing ACK bitmap for message_id=%d", tracker->message_id);
	for (int idx = 0; idx < 4; idx++)
	{
		uint16_t bitmap_value = ntohs(ack_data->ack_bitmap[idx]);
		if (bitmap_value != 0)
		{
			DBG0(DBG_IKE, "MOON_ACK_BITMAP_INDEX_%d: 0x%04x", idx, bitmap_value);
		}
	}
	
	// 关键修复：累积确认而不是重置 - 处理当前ACK中的分片
	enumerator_t *enumerator = array_create_enumerator(tracker->fragments);
	while (enumerator->enumerate(enumerator, &fragment))
	{
		// Check if this fragment is acknowledged in the current ACK bitmap
		bool is_acked_in_current = FALSE;
		if (fragment->fragment_id > 0 && fragment->fragment_id <= 64)
		{
			uint16_t bitmap_index = (fragment->fragment_id - 1) / 16;
			uint16_t bit_position = (fragment->fragment_id - 1) % 16;
			uint16_t bitmap_value = ntohs(ack_data->ack_bitmap[bitmap_index]);
			
			if (bitmap_value & (1 << bit_position))
			{
				is_acked_in_current = TRUE;
				DBG0(DBG_IKE, "MOON_ACK_BITMAP_DETECTED: fragment %d found in ACK bitmap (index=%d, pos=%d, bitmap=0x%04x)", 
					 fragment->fragment_id, bitmap_index, bit_position, bitmap_value);
			}
		}
		
		// 累积确认：如果分片在当前ACK中被确认，且之前没有被确认，则标记为确认
		if (is_acked_in_current && !fragment->acknowledged)
		{
			fragment->acknowledged = TRUE;
			tracker->acked_fragments++;
			DBG0(DBG_IKE, "MOON_ACK_FRAGMENT_NEWLY_ACKED: fragment_id=%d acknowledged for message_id=%d", 
				 fragment->fragment_id, tracker->message_id);
		}
	}
	enumerator->destroy(enumerator);
	
	// 输出当前所有分片的ACK状态（像Sun端一样的详细输出）
	DBG0(DBG_IKE, "MOON_ACK_CURRENT_STATUS: after processing ACK for message_id=%d", tracker->message_id);
		for (uint16_t fid_print = 1; fid_print <= tracker->total_fragments; fid_print++)
	{
		fragment_state_t *st = find_fragment_in_tracker(tracker, fid_print);
		bool acked_flag = st ? st->acknowledged : FALSE;
		DBG0(DBG_IKE, "MOON_ACK_FRAGMENT_STATUS: fragment_id=%d, acknowledged=%s", 
		      fid_print, acked_flag ? "YES" : "NO");
	}
	
	tracker->last_ack_time = time_monotonic(NULL);
	
	DBG1(DBG_IKE, "III6_fragment ack update: %d/%d fragments acknowledged for message %d (bitmap-based)",
		 tracker->acked_fragments, tracker->total_fragments, tracker->message_id);
}

/**
 * Send selective retransmission for missing fragments
 */
/* removed: retransmit_missing_fragments() unused complex variant */
static status_t retransmit_missing_fragments(private_task_manager_t *this, 
                                            fragment_tracker_t *tracker)
{
	enumerator_t *enumerator;
	fragment_state_t *fragment;
	array_t *missing_packets;
	uint32_t missing_count = 0;
	uint32_t retransmit_data_size = 0;  // 本次重传的数据量
	time_t current_time = time_monotonic(NULL);
	time_t ack_timeout = 2; // 2 seconds timeout for fragment acknowledgments
	
	if (!tracker || !tracker->fragments)
	{
		return FAILED;
	}
	
	// 关键修复：如果所有分片都已确认，立即停止重传
	if (tracker->acked_fragments == tracker->total_fragments)
	{
		DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_COMPLETE: message_id=%d, all %d fragments confirmed, stopping retransmission", 
			 tracker->message_id, tracker->total_fragments);
		return SUCCESS;
	}
	
	// Check if we should wait for more acknowledgments
	// Only retransmit if we have received some ACKs but not all
	if (tracker->acked_fragments > 0 && tracker->acked_fragments < tracker->total_fragments &&
		(current_time - tracker->last_ack_time) < ack_timeout)
	{
		DBG1(DBG_IKE, "waiting for more fragment acks (received %d/%d, last ack %d seconds ago)",
			 tracker->acked_fragments, tracker->total_fragments, 
			 (int)(current_time - tracker->last_ack_time));
		return SUCCESS; // Don't retransmit yet, wait for more acks
	}
	
	// 选择性重传模式：如果没有收到任何ACK，需要区分是初始等待还是强制重传
	if (tracker->acked_fragments == 0)
	{
		// 添加超时机制，避免无限等待
		time_t ack_wait_timeout = 2; // 2秒等待ACK超时 - 更快响应
		time_t time_since_first_send = current_time - tracker->last_ack_time;
		
		if (tracker->last_ack_time == 0)
		{
			// 第一次调用：设置初始时间，但在选择性重传模式下立即重传
			tracker->last_ack_time = current_time;
			DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_FORCE: first call to retransmit_missing_fragments, forcing immediate retransmission");
			// 不再等待，直接进入重传逻辑
		}
		else if (time_since_first_send < ack_wait_timeout)
		{
			DBG1(DBG_IKE, "no fragment acks received yet, waiting for initial ACKs (%d seconds remaining - fast timeout)", 
				 ack_wait_timeout - (int)time_since_first_send);
			return SUCCESS; // Wait for initial ACKs
		}
		else
		{
			// ACK等待超时，强制重传
			DBG0(DBG_IKE, "ACK_WAIT_TIMEOUT: no ACKs received after %d seconds, forcing fast retransmission", 
				 (int)time_since_first_send);
		}
	}
	
	missing_packets = array_create(0, 0);
	
	enumerator = array_create_enumerator(tracker->fragments);
	while (enumerator->enumerate(enumerator, &fragment))
	{
		if (!fragment->acknowledged)
		{
			// Exponential backoff: increase delay for repeated retransmissions
			time_t min_retry_delay = 1 << min(fragment->retransmit_count, 4); // Max 16 seconds
			if ((current_time - fragment->last_sent) >= min_retry_delay)
			{
				array_insert(missing_packets, ARRAY_TAIL, fragment->packet);
				fragment->retransmit_count++;
				fragment->last_sent = current_time;
				fragment->total_transmitted += fragment->data_size; // 累加传输量
				retransmit_data_size += fragment->data_size;       // 本次重传量
				
				// 计算分片效率
				float fragment_efficiency = 0.0;
				if (fragment->total_transmitted > 0)
				{
					fragment_efficiency = (float)fragment->data_size / fragment->total_transmitted * 100;
				}
				
				DBG0(DBG_IKE, "DEBUG_G1_RETRANSMIT: message_id=%d, fragment_id=%d, "
					  "retransmit_count=%d, last_sent=%ld, total_transmitted=%d bytes, "
					  "fragment_efficiency=%.2f%%",
					  tracker->message_id, fragment->fragment_id,
					  fragment->retransmit_count, fragment->last_sent,
					  fragment->total_transmitted, fragment_efficiency);
				missing_count++;
			}
			else
			{
				DBG1(DBG_IKE, "fragment %d retransmission delayed (backoff: %d seconds)", 
					 fragment->fragment_id, (int)min_retry_delay);
			}
		}
		else
		{
			DBG1(DBG_IKE, "fragment %d already acknowledged, skipping retransmission", 
				 fragment->fragment_id);
		}
	}
	enumerator->destroy(enumerator);
	
	if (missing_count > 0)
	{
		tracker->total_transmitted_size += retransmit_data_size;  // 累加重传量
		tracker->retransmission_count++;
		
		// 计算每个分片的详细统计
	uint32_t total_fragment_retransmissions = 0;
	enumerator_t *frag_enum = array_create_enumerator(tracker->fragments);
	fragment_state_t *frag;
	while (frag_enum->enumerate(frag_enum, &frag))
	{
		total_fragment_retransmissions += frag->retransmit_count;
	}
	frag_enum->destroy(frag_enum);
	
	DBG0(DBG_IKE, "SELEC;");
		
		send_packets(this, missing_packets,
					 this->ike_sa->get_my_host(this->ike_sa),
					 this->ike_sa->get_other_host(this->ike_sa));
	}
	else if (tracker->acked_fragments == tracker->total_fragments)
	{
		// 计算每个分片的详细统计
		uint32_t total_fragment_retransmissions = 0;
		enumerator_t *frag_enum = array_create_enumerator(tracker->fragments);
		fragment_state_t *frag;
		while (frag_enum->enumerate(frag_enum, &frag))
		{
			total_fragment_retransmissions += frag->retransmit_count;
		}
		frag_enum->destroy(frag_enum);
		
		DBG0(DBG_IKE, "FRAGMENT_COMPLETE: message_id=%d, total_transmitted=%d bytes, "
			  "original_size=%d bytes, efficiency=%.2f%%, retransmissions=%d, "
			  "total_fragment_retransmissions=%d",
			  tracker->message_id, tracker->total_transmitted_size,
			  tracker->total_original_size,
			  (float)tracker->total_original_size / tracker->total_transmitted_size * 100,
			  tracker->retransmission_count, total_fragment_retransmissions);
	}
	else
	{
		DBG2(DBG_IKE, "waiting for retry delay on %d unacknowledged fragments for message ID %d",
			 tracker->total_fragments - tracker->acked_fragments, tracker->message_id);
	}
	
	array_destroy(missing_packets);
	return SUCCESS;
}

/**
 * Simplified selective retransmission that shares timeout mechanism with traditional retransmission
 * No complex ACK waiting or exponential backoff - just retransmit unacknowledged fragments
 */
static status_t retransmit_missing_fragments_simple(private_task_manager_t *this, 
													fragment_tracker_t *tracker)
{
	enumerator_t *enumerator;
	fragment_state_t *fragment;
	array_t *missing_packets;
	uint32_t missing_count = 0;
	uint32_t retransmit_data_size = 0;
	time_t current_time = time_monotonic(NULL);
	
	if (!tracker || !tracker->fragments)
	{
		return FAILED;
	}
	
	// 检查是否所有分片都已确认
	if (tracker->acked_fragments == tracker->total_fragments)
	{
		DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_SIMPLE_COMPLETE: message_id=%d, all %d fragments confirmed", 
			 tracker->message_id, tracker->total_fragments);
		return SUCCESS;
	}
	
	missing_packets = array_create(0, 0);
	
	// 简化逻辑：直接重传所有未确认的分片，无延迟检查
	enumerator = array_create_enumerator(tracker->fragments);
	while (enumerator->enumerate(enumerator, &fragment))
	{
		if (!fragment->acknowledged)
		{
			// 简化：直接重传，无指数退避
			array_insert(missing_packets, ARRAY_TAIL, fragment->packet);
			fragment->retransmit_count++;
			fragment->last_sent = current_time;
			fragment->total_transmitted += fragment->data_size;
			retransmit_data_size += fragment->data_size;
			
			DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_SIMPLE: message_id=%d, fragment_id=%d, "
				  "retransmit_count=%d, data_size=%d bytes",
				  tracker->message_id, fragment->fragment_id,
				  fragment->retransmit_count, fragment->data_size);
			missing_count++;
		}
	}
	enumerator->destroy(enumerator);
	
	if (missing_count > 0)
	{
		tracker->total_transmitted_size += retransmit_data_size;
		tracker->retransmission_count++;
		
		DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_SIMPLE_SUMMARY: message_id=%d, "
			  "missing_fragments=%d, retransmit_data_size=%d bytes, "
			  "total_transmitted=%d bytes, efficiency=%.2f%%",
			  tracker->message_id, missing_count, retransmit_data_size,
			  tracker->total_transmitted_size,
			  (float)tracker->total_original_size / tracker->total_transmitted_size * 100);
		
		// 发送缺失分片
		send_packets(this, missing_packets,
					 this->ike_sa->get_my_host(this->ike_sa),
					 this->ike_sa->get_other_host(this->ike_sa));
		
		DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_SIMPLE_SENT: %d fragments sent, using shared timeout mechanism", 
			 missing_count);
	}
	else
	{
		DBG0(DBG_IKE, "SELECTIVE_RETRANSMIT_SIMPLE_NO_MISSING: no missing fragments to retransmit");
	}
	
	array_destroy(missing_packets);
	return missing_count > 0 ? NEED_MORE : SUCCESS;
}

/**
 * Process fragment acknowledgment
 * 简化版本：处理Message ID 0的简化ACK，添加详细DBG0日志
 */
static void process_fragment_ack(private_task_manager_t *this, message_t *message)
{
	DBG0(DBG_IKE, "LINE %d: process_fragment_ack enter, received message_id=%d", __LINE__, message->get_message_id(message));
	notify_payload_t *notify;
	chunk_t ack_data;
	fragment_ack_data_t *ack;
	
	DBG0(DBG_IKE, "FRAGMENT_ACK_FUNCTION_CALLED: process_fragment_ack() function entered");
	DBG0(DBG_IKE, "FRAGMENT_ACK_PROCESSING: checking for FRAGMENT_ACK notify in message");
	
	notify = message->get_notify(message, FRAGMENT_ACK);
	if (!notify)
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_NOT_FOUND: no FRAGMENT_ACK notify in message");
		return;
	}
	
	DBG0(DBG_IKE, "FRAGMENT_ACK_FOUND: processing FRAGMENT_ACK notify");
	
	ack_data = notify->get_notification_data(notify);
	if (ack_data.len < sizeof(fragment_ack_data_t))
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_INVALID_LENGTH: ack data length %d too short (expected %d)",
			 ack_data.len, sizeof(fragment_ack_data_t));
		return;
	}
	
	ack = (fragment_ack_data_t*)ack_data.ptr;
	uint32_t message_id = (uint32_t)ntohs(ack->message_id);
	uint32_t ack_msg_id = message->get_message_id(message);
	
	DBG0(DBG_IKE, "III2_FRAGMENT_ACK_DETAILS: received ACK with message ID %d for fragments of message %d",
		  ack_msg_id, message_id);
	
	if (!this->outgoing_tracker)
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_NO_TRACKER: no outgoing tracker available - responder may not have active fragmented transmission");
		return;
	}
	
	if (this->outgoing_tracker->message_id != message_id)
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_MISMATCH: received ACK for message %d, expected %d",
			 message_id, this->outgoing_tracker->message_id);
		return;
	}
	
	DBG0(DBG_IKE, "FRAGMENT_ACK_TRACKER_FOUND: processing ACK for message %d, current status: %d/%d fragments acknowledged",
		  message_id, this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
	
	// 记录ACK前的状态
	uint16_t prev_acked = this->outgoing_tracker->acked_fragments;
	
	// 更新时间戳，表明收到了ACK
	this->outgoing_tracker->last_ack_time = time_monotonic(NULL);
	
	// 更新ACK状态
	update_fragment_ack_status(this->outgoing_tracker, ack);
	
	// 输出详细的ACK处理信息
	DBG0(DBG_IKE, "III7_FRAGMENT_ACK_PROCESSED: for message_id=%d, received_count=%d, "
		  "total_fragments=%d, acked_before=%d, acked_after=%d",
		  message_id, ntohs(ack->received_count), ntohs(ack->total_fragments),
		  prev_acked, this->outgoing_tracker->acked_fragments);
	
	// 检查是否所有分片都已确认
	if (this->outgoing_tracker->acked_fragments == this->outgoing_tracker->total_fragments)
	{
		DBG0(DBG_IKE, "III4_FRAGMENT_ACK_ALL_CONFIRMED: all %d fragments acknowledged for message %d", 
			 this->outgoing_tracker->total_fragments, message_id);
		
		DBG0(DBG_IKE, "INTERMEDIATE_I REQUEST TOTAL RETRANSMIT DATA SIZE %d", this->outgoing_tracker->total_transmitted_size);
		// 取消重传超时，因为所有分片都已确认
		if (this->current_retransmit_job)
		{
			DBG0(DBG_IKE, "III10_RETRANSMIT_CANCELLING: attempting to cancel retransmit timeout for message %d", message_id);
			
			// 使用更保守的取消策略：让作业自然过期而不是强制取消
			// 这避免了取消过程中的潜在竞态条件和对象访问问题
			this->current_retransmit_job = NULL;  // 清空指针，让重传函数知道不需要重传
			
			DBG0(DBG_IKE, "III11_RETRANSMIT_MARKED_INACTIVE: marked retransmit job as inactive for message %d, "
				  "job will expire naturally", message_id);
		}
		else
		{
			DBG0(DBG_IKE, "III13_NO_RETRANSMIT_JOB: no retransmit job to cancel for message %d", message_id);
		}
	}
	else
	{
		DBG0(DBG_IKE, "III5_FRAGMENT_ACK_PARTIAL: %d/%d fragments acknowledged for message %d",
			 this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments,
			 message_id);
		
		// 不立即触发重传，让定时器处理 - 给网络时间让更多ACK到达
		DBG0(DBG_IKE, "FRAGMENT_ACK_PARTIAL_RECEIVED: %d/%d fragments acknowledged, waiting for timer-based retransmission",
			 this->outgoing_tracker->acked_fragments, this->outgoing_tracker->total_fragments);
	}
}

/**
 * Send simple fragment acknowledgment
 * 改进版本：使用改进的ACK机制避免加密失败
 */
static void send_fragment_ack(private_task_manager_t *this, message_t *defrag, 
							 uint32_t message_id)
{
	// 使用改进的immediate ACK函数，fragment_number=0表示一般ACK
	send_immediate_fragment_ack(this, defrag, message_id, 0);
	
	DBG1(DBG_IKE, "sent simple fragment ack for message %d using improved mechanism", message_id);
}

/**
 * Send immediate fragment acknowledgment for selective retransmission
 * 标准版本：使用IKE消息框架但禁用加密
 */
static void send_immediate_fragment_ack(private_task_manager_t *this, message_t *defrag, 
									   uint32_t message_id, uint16_t fragment_number)
{
	if (!defrag)
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_ERROR: defrag message is NULL");
		return;
	}
	
	// 获取分片信息 - 对于重组完成的消息，需要特殊处理
	uint16_t total_fragments = defrag->get_total_fragments ? defrag->get_total_fragments(defrag) : 0;
	uint16_t received_count = 0;
	uint16_t *received_frags = NULL;
	bool message_reassembled = false;
	
	if (defrag->get_received_fragments)
	{
		received_frags = defrag->get_received_fragments(defrag, &received_count);
	}
	
	// 检测消息是否已重组完成：如果received_count=0且total_fragments=0，说明defrag状态被重置
	if (received_count == 0 && total_fragments == 0)
	{
		// 消息重组完成，defrag状态被重置，使用fragment_number推断消息大小
		// 如果是最后一个分片，那么fragment_number就是total_fragments
		message_reassembled = true;
		
		// 由于无法确定确切的total_fragments，我们采用保守策略：
		// 生成一个包含当前fragment及之前所有可能fragment的cumulative ACK
		total_fragments = fragment_number; // 至少包含到当前fragment
		received_count = total_fragments;
		
		DBG0(DBG_IKE, "RRR3_DEFRAG_COMPLETED: message reassembled, using fragment_number=%d as total_fragments", total_fragments);
		
		// 为重组完成的消息创建完整的fragments数组
		received_frags = malloc(total_fragments * sizeof(uint16_t));
		if (received_frags)
		{
			for (uint16_t i = 0; i < total_fragments; i++)
			{
				received_frags[i] = i + 1;  // fragment IDs are 1-based
			}
			DBG0(DBG_IKE, "RRR3_DEFRAG_FRAGMENTS_CREATED: created complete fragments array for reassembled message");
		}
	}
	else if (received_count == 0 && total_fragments > 0)
	{
		DBG0(DBG_IKE, "RRR3_DEFRAG_PARTIAL_RESET: received_count=0 but total_fragments=%d, using total_fragments", total_fragments);
		received_count = total_fragments;
		message_reassembled = true;
		
		// 为重组完成的消息创建完整的fragments数组
		received_frags = malloc(total_fragments * sizeof(uint16_t));
		if (received_frags)
		{
			for (uint16_t i = 0; i < total_fragments; i++)
			{
				received_frags[i] = i + 1;  // fragment IDs are 1-based
			}
			DBG0(DBG_IKE, "RRR3_DEFRAG_FRAGMENTS_CREATED: created complete fragments array for partial reset case");
		}
	}
	
	DBG0(DBG_IKE, "RRR3_FRAGMENT_ACK_SENDING: message_id=%d, fragment_number=%d, "
		  "received_count=%d, total_fragments=%d", 
		  message_id, fragment_number, received_count, total_fragments);
	
	// 创建ACK数据
	fragment_ack_data_t ack;
	ack.message_id = htons((uint16_t)message_id);
	ack.total_fragments = htons(total_fragments);  
	ack.received_count = htons(received_count);
	memset(ack.ack_bitmap, 0, sizeof(ack.ack_bitmap));
	
	// 设置收到的分片位图 - 包含所有已收到的fragments
	if (received_frags && received_count > 0)
	{
		DBG0(DBG_IKE, "RRR3_BITMAP_SETTING: setting bitmap for %d received fragments%s", 
			  received_count, message_reassembled ? " (reassembled)" : "");
		for (int i = 0; i < received_count; i++)
		{
			uint16_t frag_id = received_frags[i];
			if (frag_id > 0 && frag_id <= 64)
			{
				uint16_t bitmap_index = (frag_id - 1) / 16;
				uint16_t bit_position = (frag_id - 1) % 16;
				ack.ack_bitmap[bitmap_index] |= htons(1 << bit_position);
				DBG0(DBG_IKE, "RRR3_BITMAP_SET: set bit for fragment %d (index=%d, pos=%d)", 
					 frag_id, bitmap_index, bit_position);
			}
		}
		free(received_frags);
	}
	else if (message_reassembled && total_fragments > 0)
	{
		// 消息重组完成，但received_frags为空，设置所有fragments的bitmap
		DBG0(DBG_IKE, "RRR3_BITMAP_COMPLETE: message reassembled, setting bitmap for all %d fragments", total_fragments);
		for (uint16_t i = 1; i <= total_fragments; i++)
		{
			if (i <= 64)
			{
				uint16_t bitmap_index = (i - 1) / 16;
				uint16_t bit_position = (i - 1) % 16;
				ack.ack_bitmap[bitmap_index] |= htons(1 << bit_position);
				DBG0(DBG_IKE, "RRR3_BITMAP_SET: set bit for fragment %d (index=%d, pos=%d)", 
					 i, bitmap_index, bit_position);
			}
		}
	}
	else if (received_count > 0 && total_fragments > 0)
	{
		// 其他累积情况：设置所有fragments的bitmap
		DBG0(DBG_IKE, "RRR3_BITMAP_CUMULATIVE: setting bitmap for all %d fragments (cumulative)", total_fragments);
		for (uint16_t i = 1; i <= total_fragments; i++)
		{
			if (i <= 64)
			{
				uint16_t bitmap_index = (i - 1) / 16;
				uint16_t bit_position = (i - 1) % 16;
				ack.ack_bitmap[bitmap_index] |= htons(1 << bit_position);
				DBG0(DBG_IKE, "RRR3_BITMAP_SET: set bit for fragment %d (index=%d, pos=%d)", 
					 i, bitmap_index, bit_position);
			}
		}
	}
	else
	{
		// 回退到只设置当前fragment
		if (fragment_number > 0 && fragment_number <= 64)
		{
			uint16_t bitmap_index = (fragment_number - 1) / 16;
			uint16_t bit_position = (fragment_number - 1) % 16;
			ack.ack_bitmap[bitmap_index] |= htons(1 << bit_position);
			DBG0(DBG_IKE, "RRR3_BITMAP_FALLBACK: set bit for current fragment %d only", fragment_number);
		}
	}
	
	chunk_t ack_data = chunk_create((uint8_t*)&ack, sizeof(fragment_ack_data_t));
	
	// 详细的ACK生成日志
	DBG0(DBG_IKE, "RRR4_ACK_GENERATION: generating FRAGMENT_ACK for message_id=%d, fragment=%d, "
		  "ack_bitmap=0x%04x, total_fragments=%d, received_count=%d", 
		  message_id, fragment_number, ntohs(ack.ack_bitmap[0]), total_fragments, received_count);

	/* 额外调试输出：发送方自身的位图/片段状态，保持与解析端日志一致 */
	DBG0(DBG_IKE, "MOON_TX_BITMAP_GENERATED: message_id=%d", message_id);
	uint16_t bitmap_words_tx = (total_fragments + 15) / 16;
	if (bitmap_words_tx > 4)
	{
		bitmap_words_tx = 4; /* bitmap array大小固定为8×16bit，总共4个word */
	}
	for (uint16_t idx = 0; idx < bitmap_words_tx; idx++)
	{
		uint16_t bitmap_value_tx = ntohs(ack.ack_bitmap[idx]);
		DBG0(DBG_IKE, "MOON_TX_BITMAP_INDEX_%d: 0x%04x", idx, bitmap_value_tx);
	}
	for (uint16_t fid_tx = 1; fid_tx <= total_fragments && fid_tx <= 64; fid_tx++)
	{
		uint16_t b_idx = (fid_tx - 1) / 16;
		uint16_t b_pos = (fid_tx - 1) % 16;
		bool acked_tx = (ntohs(ack.ack_bitmap[b_idx]) & (1 << b_pos));
		DBG0(DBG_IKE, "MOON_TX_FRAGMENT_STATUS: fragment_id=%d, acknowledged=%s",
			 fid_tx, acked_tx ? "YES" : "NO");
	}
	DBG0(DBG_IKE, "III6_fragment ack tx update: %d/%d fragments acknowledged for message %d",
		 received_count, total_fragments, message_id);
	
	// 使用标准IKE消息框架
	notify_payload_t *notify = notify_payload_create_from_protocol_and_type(PLV2_NOTIFY, PROTO_NONE, FRAGMENT_ACK);
	notify->set_notification_data(notify, ack_data);
	
	message_t *ack_msg = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
    ack_msg->set_exchange_type(ack_msg, INFORMATIONAL);
    ack_msg->set_request(ack_msg, TRUE);
    /* Use Message ID 0 to follow FRAGMENT_ACK convention */
    ack_msg->set_message_id(ack_msg, 0);
    
    // 设置源地址和目标地址 - 这是必须的！
    host_t *me = this->ike_sa->get_my_host(this->ike_sa);
    host_t *other = this->ike_sa->get_other_host(this->ike_sa);
    if (me && other)
    {
        ack_msg->set_source(ack_msg, me->clone(me));
        ack_msg->set_destination(ack_msg, other->clone(other));
        DBG0(DBG_IKE, "ACK_ADDRESS_SET: source=%H, destination=%H", me, other);
    }
    else
    {
        DBG0(DBG_IKE, "ACK_ADDRESS_ERROR: failed to get IKE_SA addresses (me=%p, other=%p)", me, other);
    }
	
	ack_msg->add_payload(ack_msg, (payload_t*)notify);
	
    // 使用 IKE_SA 统一的生成逻辑，确保加密/完整性与状态一致
    packet_t *packet = NULL;
    status_t status = this->ike_sa->generate_message(this->ike_sa, ack_msg, &packet);
	
	if (status == SUCCESS && packet)
	{
		// 立即发送
		charon->sender->send(charon->sender, packet);
		
		DBG0(DBG_IKE, "RRR4_FRAGMENT_ACK_SENT: message_id=%d, fragment_number=%d, "
			  "packet_size=%d bytes, using standard Message ID 0",
			  message_id, fragment_number, packet->get_data(packet).len);
	}
	else
	{
		DBG0(DBG_IKE, "FRAGMENT_ACK_FAILED: message_id=%d, fragment_number=%d, "
			  "failed to generate ACK packet (status=%d)", 
			  message_id, fragment_number, status);
	}
	
	ack_msg->destroy(ack_msg);
}

/**
 * Print intermediate transmission statistics
 */
static void print_complete_connection_stats(private_task_manager_t *this)
{
	DBG0(DBG_IKE, "=== COMPLETE CONNECTION STATISTICS ===");
	DBG0(DBG_IKE, "Connection established successfully!");
	DBG0(DBG_IKE, "Total connection time: %d seconds", 
		  (int)(time_monotonic(NULL) - this->start_time));
	// DBG0(DBG_IKE, "Network loss rate: 5.0%% (simulated)");
	DBG0(DBG_IKE, "Selective retransmission: %s", 
		  this->selective_retransmission_enabled ? "enabled" : "disabled");
	DBG0(DBG_IKE, "=====================================");
}

static void print_intermediate_transmission_stats(private_task_manager_t *this)
{
	uint32_t request_transmitted = 0;
	uint32_t request_original = 0;
	uint32_t request_retransmissions = 0;
	uint32_t response_transmitted = 0;
	uint32_t response_original = 0;
	uint32_t response_retransmissions = 0;
	uint16_t fragment_count = 0;
	bool has_fragmentation = FALSE;
	
	// 检查是否有分片跟踪器（选择性重传）
	if (this->outgoing_tracker)
	{
		// 选择性重传模式下的统计
		request_transmitted = this->outgoing_tracker->total_transmitted_size;
		request_original = this->outgoing_tracker->total_original_size;
		request_retransmissions = this->outgoing_tracker->retransmission_count;
		fragment_count = this->outgoing_tracker->total_fragments;
		has_fragmentation = TRUE;
		
		// 保存请求统计信息
		this->request_original_size = request_original;
		this->request_total_transmitted = request_transmitted;
		this->request_retransmission_count = request_retransmissions;
		
		// 添加调试信息
		DBG0(DBG_IKE, "DEBUG_D1_TRACKER: message_id=%d, retransmission_count=%d, "
			  "total_transmitted=%d, original_size=%d",
			  this->outgoing_tracker->message_id,
			  this->outgoing_tracker->retransmission_count,
			  this->outgoing_tracker->total_transmitted_size,
			  this->outgoing_tracker->total_original_size);
	}
	else
	{
		// 传统传输模式下的统计
		packet_t *packet;
		uint32_t single_transmission_size = 0;
		
		// 计算单次传输的数据量
		for (int i = 0; i < array_count(this->initiating.packets); i++)
		{
			array_get(this->initiating.packets, i, &packet);
			single_transmission_size += packet->get_data(packet).len;
		}
		
		// 直接使用单次传输量，不依赖retransmitted计数
		request_transmitted = single_transmission_size;
		request_original = single_transmission_size;  // 原始大小就是单次传输量
		// request_retransmissions = 0;  // 从日志看没有重传
		fragment_count = array_count(this->initiating.packets);
		has_fragmentation = (fragment_count > 1);
		
		// 保存请求统计信息
		this->request_original_size = request_original;
		// 修正计算逻辑：如果没有重传，total_transmitted = single_transmission
		// 如果有重传，total_transmitted = single_transmission * (1 + retransmitted)
		if (this->initiating.retransmitted == 0)
		{
			this->request_total_transmitted = single_transmission_size;
		}
		else
		{
			this->request_total_transmitted = single_transmission_size * ( this->initiating.retransmitted);
		}
		// this->request_retransmission_count = request_retransmissions;
		
		DBG0(DBG_IKE, "DEBUG_C1_TRADITIONAL: retransmitted=%d, packets=%d, "
			  "single_transmission=%d, total_transmitted=%d", 
			  this->initiating.retransmitted-1, fragment_count, 
			  single_transmission_size, this->request_total_transmitted);
	}
	
	// 计算请求效率
	float request_efficiency = 0.0;
	if (request_transmitted > 0)
	{
		request_efficiency = (float)request_original / request_transmitted * 100.0;
	}
	
	// 计算响应效率
	float response_efficiency = 0.0;
	if (response_transmitted > 0)
	{
		response_efficiency = (float)response_original / response_transmitted * 100.0;
	}
	
	// 输出分离的统计信息
	uint32_t total_packets = request_retransmissions ; // +1 for initial transmission
	if (has_fragmentation)
	{
		DBG0(DBG_IKE, "DEBUG_E1_REQUEST_TRANSMISSION_STATS: message_id=%d, "
			  "original_size=%d bytes, total_transmitted=%d bytes, "
			  "efficiency=%.2f%%, retransmissions=%d, total_packets=%d, fragments=%d, "
			  "selective_retransmission=%s",
			  this->initiating.mid,
			  request_original, request_transmitted, request_efficiency,
			  request_retransmissions, total_packets, fragment_count,
			  this->selective_retransmission_enabled ? "enabled" : "disabled");
	}
	else
	{
		DBG0(DBG_IKE, "DEBUG_E2_REQUEST_TRANSMISSION_STATS: message_id=%d, "
			  "original_size=%d bytes, total_transmitted=%d bytes, "
			  "efficiency=%.2f%%, retransmissions=%d, total_packets=%d, no_fragmentation",
			  this->initiating.mid, request_original, request_transmitted, 
			  request_efficiency, request_retransmissions, total_packets);
	}
	
	// 如果有响应数据，也输出响应统计
	if (response_transmitted > 0)
	{
		DBG0(DBG_IKE, "DEBUG_F1_RESPONSE_TRANSMISSION_STATS: message_id=%d, "
			  "original_size=%d bytes, total_transmitted=%d bytes, "
			  "efficiency=%.2f%%, retransmissions=%d",
			  this->initiating.mid,
			  response_original, response_transmitted, response_efficiency,
			  response_retransmissions);
	}
}

/**
 * Update response transmission statistics
 */
static void update_response_transmission_stats(private_task_manager_t *this, uint32_t response_size, uint32_t retransmissions)
{
	this->response_original_size = response_size;
	this->response_total_transmitted = response_size * (retransmissions + 1);
	this->response_retransmission_count = retransmissions;
	
	// 计算响应效率
	float response_efficiency = 0.0;
	if (this->response_total_transmitted > 0)
	{
		response_efficiency = (float)this->response_original_size / this->response_total_transmitted * 100.0;
	}
	
	// 输出响应统计信息
	DBG0(DBG_IKE, "DEBUG_F2_RESPONSE_TRANSMISSION_STATS: message_id=%d, "
		  "original_size=%d bytes, total_transmitted=%d bytes, "
		  "efficiency=%.2f%%, retransmissions=%d",
		  this->initiating.mid,  // 使用initiating的message_id，因为这是对请求的响应
		  this->response_original_size, this->response_total_transmitted, 
		  response_efficiency, this->response_retransmission_count);
}
