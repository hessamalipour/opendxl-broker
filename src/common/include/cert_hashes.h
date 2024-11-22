/******************************************************************************
 * Copyright (c) 2018 McAfee LLC - All Rights Reserved.
 *****************************************************************************/

#ifndef CERT_HASHES_H
#define CERT_HASHES_H

#include "../../mqtt-core/src/uthash.h"

/**
 * Structure that contains hashes of certificates (used with UTHASH)
 */
struct cert_hashes {
    /** The certificate hash (using SHA-256) */
    const char *cert_sha256;  // Updated to use SHA-256
    /** The UT Hash handle */
    UT_hash_handle hh;
};

#endif
