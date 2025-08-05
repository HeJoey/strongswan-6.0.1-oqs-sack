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

#ifndef OQS_DRBG_H_
#define OQS_DRBG_H_

#include <crypto/drbgs/drbg.h>

/**
 * Initialize the OQS DRBG
 */
void oqs_drbg_init(void);

/**
 * Deinitialize the OQS DRBG
 */
void oqs_drbg_deinit(void);

/**
 * Set the DRBG for OQS random number generation
 */
void oqs_drbg_set(drbg_t *drbg);

/**
 * OQS DRBG random number generator function
 */
void oqs_drbg_rand(uint8_t *random_array, size_t bytes_to_read);

#endif /* OQS_DRBG_H_ */ 