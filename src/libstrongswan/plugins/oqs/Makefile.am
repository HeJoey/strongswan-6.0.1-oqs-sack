AM_CPPFLAGS = \
	-I$(top_srcdir)/src/libstrongswan \
	-I$(top_srcdir)/src/libstrongswan/plugins/oqs \
	-I$(top_srcdir)/src/libstrongswan/plugins/oqs/include \
	-I$(top_srcdir)/src/libstrongswan/plugins/oqs/build/include \
	-I$(top_srcdir)/src/libstrongswan/plugins/oqs/liboqs/build/include

AM_CFLAGS = \
	$(PLUGIN_CFLAGS)

if MONOLITHIC
noinst_LTLIBRARIES = libstrongswan-oqs.la
else
plugin_LTLIBRARIES = libstrongswan-oqs.la
endif

libstrongswan_oqs_la_SOURCES = \
	oqs_plugin.c oqs_plugin.h \
	oqs_kem.c oqs_kem.h \
	oqs_drbg.c oqs_drbg.h

libstrongswan_oqs_la_LDFLAGS = -module -avoid-version
libstrongswan_oqs_la_LIBADD = -loqs -lcrypto
libstrongswan_oqs_la_LDFLAGS += -L$(top_srcdir)/src/libstrongswan/plugins/oqs/liboqs/build/lib

# Test programs for HQC_128
check_PROGRAMS = test_hqc_128_simple test_hqc_128

# Simple test using liboqs directly
test_hqc_128_simple_SOURCES = test_hqc_128_simple.c
test_hqc_128_simple_LDADD = -loqs
test_hqc_128_simple_LDFLAGS = -L$(top_srcdir)/src/libstrongswan/plugins/oqs/liboqs/build/lib

# Full test using strongSwan API
test_hqc_128_SOURCES = test_hqc_128.c
test_hqc_128_LDADD = libstrongswan-oqs.la \
	$(top_srcdir)/src/libstrongswan/libstrongswan.la \
	-lcrypto -loqs
test_hqc_128_LDFLAGS = -L$(top_srcdir)/src/libstrongswan/plugins/oqs/liboqs/build/lib