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

#ifndef OQS_PLUGIN_H_
#define OQS_PLUGIN_H_

#include <plugins/plugin.h>

typedef struct oqs_plugin_t oqs_plugin_t;

/**
 * OQS plugin
 */
struct oqs_plugin_t {

	/**
	 * implements plugin interface
	 */
	plugin_t plugin;
};

/**
 * Create a oqs_plugin instance.
 */
plugin_t *oqs_plugin_create();

#endif /* OQS_PLUGIN_H_ */ 