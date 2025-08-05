/*
 * Simple test for HQC_128 KEM
 * Tests the basic functionality using liboqs directly
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <oqs/oqs.h>

#define TEST_ITERATIONS 5

static void print_hex(const char *label, const uint8_t *data, size_t len)
{
	printf("%s (%zu bytes): ", label, len);
	for (size_t i = 0; i < len && i < 16; i++)
	{
		printf("%02x", data[i]);
	}
	if (len > 16)
	{
		printf("...");
	}
	printf("\n");
}

static bool test_hqc_128_single(int iteration)
{
	OQS_KEM *kem = NULL;
	uint8_t *public_key = NULL;
	uint8_t *secret_key = NULL;
	uint8_t *ciphertext = NULL;
	uint8_t *shared_secret_a = NULL;
	uint8_t *shared_secret_b = NULL;
	OQS_STATUS rc;
	bool success = false;

	printf("\n=== Test HQC_128 Iteration %d ===\n", iteration);

	/* Create KEM instance */
	kem = OQS_KEM_new(OQS_KEM_alg_hqc_128);
	if (kem == NULL)
	{
		printf("ERROR: Failed to create HQC_128 KEM instance\n");
		return false;
	}

	printf("KEM created successfully\n");
	printf("Public key length: %zu\n", kem->length_public_key);
	printf("Secret key length: %zu\n", kem->length_secret_key);
	printf("Ciphertext length: %zu\n", kem->length_ciphertext);
	printf("Shared secret length: %zu\n", kem->length_shared_secret);

	/* Allocate memory */
	public_key = malloc(kem->length_public_key);
	secret_key = malloc(kem->length_secret_key);
	ciphertext = malloc(kem->length_ciphertext);
	shared_secret_a = malloc(kem->length_shared_secret);
	shared_secret_b = malloc(kem->length_shared_secret);

	if (!public_key || !secret_key || !ciphertext || 
		!shared_secret_a || !shared_secret_b)
	{
		printf("ERROR: Memory allocation failed\n");
		goto cleanup;
	}

	/* Generate keypair */
	rc = OQS_KEM_keypair(kem, public_key, secret_key);
	if (rc != OQS_SUCCESS)
	{
		printf("ERROR: Keypair generation failed\n");
		goto cleanup;
	}
	printf("Keypair generated successfully\n");
	print_hex("Public key", public_key, kem->length_public_key);

	/* Encapsulate (Bob's side) */
	rc = OQS_KEM_encaps(kem, ciphertext, shared_secret_a, public_key);
	if (rc != OQS_SUCCESS)
	{
		printf("ERROR: Encapsulation failed\n");
		goto cleanup;
	}
	printf("Encapsulation successful\n");
	print_hex("Ciphertext", ciphertext, kem->length_ciphertext);
	print_hex("Bob's shared secret", shared_secret_a, kem->length_shared_secret);

	/* Decapsulate (Alice's side) */
	rc = OQS_KEM_decaps(kem, shared_secret_b, ciphertext, secret_key);
	if (rc != OQS_SUCCESS)
	{
		printf("ERROR: Decapsulation failed\n");
		goto cleanup;
	}
	printf("Decapsulation successful\n");
	print_hex("Alice's shared secret", shared_secret_b, kem->length_shared_secret);

	/* Verify shared secrets match */
	if (memcmp(shared_secret_a, shared_secret_b, kem->length_shared_secret) == 0)
	{
		printf("SUCCESS: Shared secrets match!\n");
		success = true;
	}
	else
	{
		printf("ERROR: Shared secrets do not match!\n");
	}

cleanup:
	/* Cleanup */
	if (public_key) free(public_key);
	if (secret_key) free(secret_key);
	if (ciphertext) free(ciphertext);
	if (shared_secret_a) free(shared_secret_a);
	if (shared_secret_b) free(shared_secret_b);
	if (kem) OQS_KEM_free(kem);

	return success;
}

int main(void)
{
	int passed = 0, total = 0;
	bool success;

	printf("HQC_128 KEM Simple Test\n");
	printf("=======================\n");

	/* Check if HQC_128 is available */
	if (!OQS_KEM_alg_is_enabled(OQS_KEM_alg_hqc_128))
	{
		printf("ERROR: HQC_128 is not enabled in this liboqs build\n");
		return 1;
	}

	printf("HQC_128 is available\n");

	/* Run tests */
	for (int i = 0; i < TEST_ITERATIONS; i++)
	{
		success = test_hqc_128_single(i + 1);
		if (success)
		{
			passed++;
		}
		total++;
	}

	/* Print results */
	printf("\n=== Test Results ===\n");
	printf("Passed: %d/%d\n", passed, total);
	printf("Success rate: %.1f%%\n", (float)passed / total * 100);

	if (passed == total)
	{
		printf("ALL TESTS PASSED! HQC_128 KEM is working correctly.\n");
		return 0;
	}
	else
	{
		printf("SOME TESTS FAILED! HQC_128 KEM has issues.\n");
		return 1;
	}
} 