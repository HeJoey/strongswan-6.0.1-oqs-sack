/*
 * Copyright (C) 2018-2020 Andreas Steffen
 * HSR Hochschule fuer Technik Rapperswil
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

#include "oqs_drbg.h"

#include <threading/thread_value.h>
#include <utils/debug.h>

#include <oqs/oqs.h>

/**
 * Thread-specific DRBG instance
 */
static thread_value_t *drbg_key;

/**
 * OQS DRBG random number generator function
 */
void oqs_drbg_rand(uint8_t *random_array, size_t bytes_to_read)
{
	drbg_t *drbg;

	drbg = drbg_key->get(drbg_key);
	if (drbg)
	{
		if (!drbg->generate(drbg, bytes_to_read, random_array))
		{
			DBG1(DBG_LIB, "OQS DRBG random number generation failed");
		}
	}
}

/**
 * Set the DRBG for OQS random number generation
 */
void oqs_drbg_set(drbg_t *drbg)
{
	if (drbg)
	{
		drbg_key->set(drbg_key, drbg);
	}
}

/**
 * Initialize the OQS DRBG
 */
void oqs_drbg_init(void)
{
	drbg_key = thread_value_create(NULL);
}

/**
 * Deinitialize the OQS DRBG
 */
void oqs_drbg_deinit(void)
{
	drbg_key->destroy(drbg_key);
} 