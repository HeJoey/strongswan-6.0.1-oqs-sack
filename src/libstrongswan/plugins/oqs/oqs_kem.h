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

#ifndef OQS_KEM_H_
#define OQS_KEM_H_

#include <crypto/key_exchange.h>

typedef struct oqs_kem_t oqs_kem_t;

/**
 * OQS KEM implementation
 */
struct oqs_kem_t {

	/**
	 * Implements key_exchange_t interface.
	 */
	key_exchange_t ke;
};

/**
 * Create a oqs_kem instance.
 */
oqs_kem_t *oqs_kem_create(key_exchange_method_t method);

#endif /* OQS_KEM_H_ */ 