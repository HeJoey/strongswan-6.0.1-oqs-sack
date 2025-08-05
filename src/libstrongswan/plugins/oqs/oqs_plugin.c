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

#include "oqs_plugin.h"
#include "oqs_kem.h"
#include "oqs_drbg.h"

#include <library.h>
#include <threading/thread_value.h>

typedef struct private_oqs_plugin_t private_oqs_plugin_t;

/**
 * private data of oqs_plugin
 */
struct private_oqs_plugin_t {

	/**
	 * public functions
	 */
	oqs_plugin_t public;
};

METHOD(plugin_t, get_name, char*,
	private_oqs_plugin_t *this)
{
	return "oqs";
}

METHOD(plugin_t, get_features, int,
	private_oqs_plugin_t *this, plugin_feature_t *features[])
{
	static plugin_feature_t f[] = {
		/* KEM-based key exchange methods */
		PLUGIN_REGISTER(KE, oqs_kem_create),
			/* ML-KEM (NIST Standard) */
			PLUGIN_PROVIDE(KE, ML_KEM_512),
			PLUGIN_PROVIDE(KE, ML_KEM_768),
			PLUGIN_PROVIDE(KE, ML_KEM_1024),
			/* Kyber */
			PLUGIN_PROVIDE(KE, KYBER_512),
			PLUGIN_PROVIDE(KE, KYBER_768),
			PLUGIN_PROVIDE(KE, KYBER_1024),
			/* BIKE */
			PLUGIN_PROVIDE(KE, BIKE_L1),
			PLUGIN_PROVIDE(KE, BIKE_L3),
			PLUGIN_PROVIDE(KE, BIKE_L5),
			/* Classic McEliece */
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_348864),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_348864F),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_460896),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_460896F),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_6688128),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_6688128F),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_6960119),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_6960119F),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_8192128),
			PLUGIN_PROVIDE(KE, CLASSIC_MCELIECE_8192128F),
			/* HQC */
			PLUGIN_PROVIDE(KE, HQC_128),
			PLUGIN_PROVIDE(KE, HQC_192),
			PLUGIN_PROVIDE(KE, HQC_256),
			/* NTRU Prime */
			PLUGIN_PROVIDE(KE, SNTRUP761),
			/* FrodoKEM */
			PLUGIN_PROVIDE(KE, FRODOKEM_640_AES),
			PLUGIN_PROVIDE(KE, FRODOKEM_640_SHAKE),
			PLUGIN_PROVIDE(KE, FRODOKEM_976_AES),
			PLUGIN_PROVIDE(KE, FRODOKEM_976_SHAKE),
			PLUGIN_PROVIDE(KE, FRODOKEM_1344_AES),
			PLUGIN_PROVIDE(KE, FRODOKEM_1344_SHAKE),
	};
	*features = f;
	return countof(f);
}

METHOD(plugin_t, destroy, void,
	private_oqs_plugin_t *this)
{
	oqs_drbg_deinit();
	free(this);
}

/*
 * see header file
 */
plugin_t *oqs_plugin_create()
{
	private_oqs_plugin_t *this;

	INIT(this,
		.public = {
			.plugin = {
				.get_name = _get_name,
				.get_features = _get_features,
				.destroy = _destroy,
			},
		},
	);

	oqs_drbg_init();

	return &this->public.plugin;
} 