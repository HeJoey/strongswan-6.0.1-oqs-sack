/*
 * Copyright (C) 2024 Test HQC_128 KEM
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>

#include "oqs_kem.h"
#include "oqs_drbg.h"

#include <utils/debug.h>
#include <crypto/key_exchange.h>
#include <crypto/drbgs/drbg.h>
#include <library.h>

/* 测试配置 */
#define TEST_ITERATIONS 10

/**
 * 打印字节数组的十六进制表示
 */
static void print_hex(const char *label, const uint8_t *data, size_t len)
{
	printf("%s (%zu bytes): ", label, len);
	for (size_t i = 0; i < len && i < 32; i++)
	{
		printf("%02x", data[i]);
	}
	if (len > 32)
	{
		printf("...");
	}
	printf("\n");
}

/**
 * 比较两个字节数组是否相等
 */
static bool compare_data(const uint8_t *data1, const uint8_t *data2, size_t len)
{
	return memcmp(data1, data2, len) == 0;
}

/**
 * 测试单个HQC_128密钥交换
 */
static bool test_hqc_128_single(int iteration)
{
	oqs_kem_t *alice_kem, *bob_kem;
	chunk_t alice_public, bob_public, alice_secret, bob_secret;
	bool success = false;

	printf("\n=== Test HQC_128 Iteration %d ===\n", iteration);

	/* 创建Alice和Bob的KEM实例 */
	alice_kem = oqs_kem_create(HQC_128);
	bob_kem = oqs_kem_create(HQC_128);

	if (!alice_kem || !bob_kem)
	{
		printf("Failed to create KEM instances\n");
		goto cleanup;
	}

	/* Alice生成密钥对并获取公钥 */
	if (!alice_kem->ke.get_public_key(&alice_kem->ke, &alice_public))
	{
		printf("Alice failed to get public key\n");
		goto cleanup;
	}
	printf("Alice generated keypair\n");
	print_hex("Alice public key", alice_public.ptr, alice_public.len);

	/* Bob设置Alice的公钥并生成密文 */
	if (!bob_kem->ke.set_public_key(&bob_kem->ke, alice_public))
	{
		printf("Bob failed to set Alice's public key\n");
		goto cleanup;
	}
	printf("Bob set Alice's public key\n");

	/* Bob获取密文（公钥） */
	if (!bob_kem->ke.get_public_key(&bob_kem->ke, &bob_public))
	{
		printf("Bob failed to get ciphertext\n");
		goto cleanup;
	}
	printf("Bob generated ciphertext\n");
	print_hex("Bob ciphertext", bob_public.ptr, bob_public.len);

	/* Alice设置Bob的密文 */
	if (!alice_kem->ke.set_public_key(&alice_kem->ke, bob_public))
	{
		printf("Alice failed to set Bob's ciphertext\n");
		goto cleanup;
	}
	printf("Alice set Bob's ciphertext\n");

	/* 获取共享密钥 */
	if (!alice_kem->ke.get_shared_secret(&alice_kem->ke, &alice_secret))
	{
		printf("Alice failed to get shared secret\n");
		goto cleanup;
	}
	if (!bob_kem->ke.get_shared_secret(&bob_kem->ke, &bob_secret))
	{
		printf("Bob failed to get shared secret\n");
		goto cleanup;
	}

	printf("Shared secrets generated\n");
	print_hex("Alice shared secret", alice_secret.ptr, alice_secret.len);
	print_hex("Bob shared secret", bob_secret.ptr, bob_secret.len);

	/* 验证共享密钥是否相同 */
	if (alice_secret.len != bob_secret.len)
	{
		printf("ERROR: Shared secret lengths differ: Alice=%zu, Bob=%zu\n",
			   alice_secret.len, bob_secret.len);
		goto cleanup;
	}

	if (!compare_data(alice_secret.ptr, bob_secret.ptr, alice_secret.len))
	{
		printf("ERROR: Shared secrets do not match!\n");
		goto cleanup;
	}

	printf("SUCCESS: Shared secrets match!\n");
	success = true;

cleanup:
	/* 清理资源 */
	if (alice_kem)
	{
		alice_kem->ke.destroy(&alice_kem->ke);
	}
	if (bob_kem)
	{
		bob_kem->ke.destroy(&bob_kem->ke);
	}
	if (alice_public.ptr)
	{
		free(alice_public.ptr);
	}
	if (bob_public.ptr)
	{
		free(bob_public.ptr);
	}
	if (alice_secret.ptr)
	{
		free(alice_secret.ptr);
	}
	if (bob_secret.ptr)
	{
		free(bob_secret.ptr);
	}

	return success;
}

/**
 * 测试HQC_128密钥交换的边界情况
 */
static bool test_hqc_128_edge_cases(void)
{
	oqs_kem_t *kem;
	chunk_t dummy_chunk;
	bool success = true;

	printf("\n=== Testing HQC_128 Edge Cases ===\n");

	/* 测试创建KEM实例 */
	kem = oqs_kem_create(HQC_128);
	if (!kem)
	{
		printf("ERROR: Failed to create KEM instance\n");
		return false;
	}

	/* 测试空数据 */
	dummy_chunk = chunk_empty;
	if (kem->ke.set_public_key(&kem->ke, dummy_chunk))
	{
		printf("ERROR: Should fail with empty chunk\n");
		success = false;
	}
	else
	{
		printf("PASS: Correctly rejected empty chunk\n");
	}

	/* 测试错误大小的数据 */
	dummy_chunk = chunk_create("test", 4);
	if (kem->ke.set_public_key(&kem->ke, dummy_chunk))
	{
		printf("ERROR: Should fail with wrong size chunk\n");
		success = false;
	}
	else
	{
		printf("PASS: Correctly rejected wrong size chunk\n");
	}

	kem->ke.destroy(&kem->ke);
	return success;
}

/**
 * 主测试函数
 */
int main(int argc, char *argv[])
{
	int passed = 0, total = 0;
	bool success;

	printf("HQC_128 KEM Test Suite\n");
	printf("======================\n");

	/* 初始化 strongSwan 库 */
	if (!library_init(NULL, "test_hqc_128"))
	{
		printf("ERROR: Failed to initialize strongSwan library\n");
		return 1;
	}

	/* 初始化调试系统 */
	lib->settings->set_bool(lib->settings, "libstrongswan.debug", true);
	lib->settings->set_int(lib->settings, "libstrongswan.debug_level", DBG_LIB);

	/* 运行基本测试 */
	printf("\nRunning %d basic HQC_128 tests...\n", TEST_ITERATIONS);
	for (int i = 0; i < TEST_ITERATIONS; i++)
	{
		success = test_hqc_128_single(i + 1);
		if (success)
		{
			passed++;
		}
		total++;
	}

	/* 运行边界情况测试 */
	printf("\nRunning edge case tests...\n");
	success = test_hqc_128_edge_cases();
	if (success)
	{
		passed++;
	}
	total++;

	/* 输出测试结果 */
	printf("\n=== Test Results ===\n");
	printf("Passed: %d/%d\n", passed, total);
	printf("Success rate: %.1f%%\n", (float)passed / total * 100);

	if (passed == total)
	{
		printf("ALL TESTS PASSED! HQC_128 KEM is working correctly.\n");
		library_deinit();
		return 0;
	}
	else
	{
		printf("SOME TESTS FAILED! HQC_128 KEM has issues.\n");
		library_deinit();
		return 1;
	}
} 