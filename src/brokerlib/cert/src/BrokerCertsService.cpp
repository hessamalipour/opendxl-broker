/******************************************************************************
 * Copyright (c) 2018 McAfee, LLC - All Rights Reserved.
 *****************************************************************************/

#include "include/brokerlib.h"
#include "include/BrokerSettings.h"
#include "include/GeneralPolicySettings.h"
#include "include/SimpleLog.h"
#include "cert/include/BrokerCertsService.h"
#include "util/include/FileUtil.h"
#include "util/include/TimeUtil.h"

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>  // Include for X509_get_ext_d2i()
#include <openssl/x509_vfy.h>
#include <openssl/objects.h>

#include "dxlcommon.h"

using namespace std;
using namespace dxl::broker;
using namespace dxl::broker::cert;
using namespace dxl::broker::util;

/** {@inheritDoc} */
BrokerCertsService& BrokerCertsService::getInstance()
{
    static BrokerCertsService instance;
    return instance;
}

/* {@inheritDoc} */
BrokerCertsService::BrokerCertsService()
{
    m_clientGuidNid = OBJ_create(
        "1.3.6.1.4.1.1230.540.1", "DxlClientGuidOID", "DXL Client GUID OID" );
    m_tenantGuidNid = OBJ_create(
        "1.3.6.1.4.1.1230.540.2", "DxlTenantOID", "DXL Tenant GUID OID" );
}

/** {@inheritDoc} */
bool BrokerCertsService::getFilesExist()
{
    return checkFilesExist();
}

/**
 * Looks up and returns the specified ASN.1 NID certificate extension value
 *
 * @return    The specified ASN.1 NID certificate extension value 
 *            (or empty string if it could not be determined)
 */
static string lookupCertExtension(int asn1nid)
{
    string retVal;
    BIO* certbio = nullptr;
    X509* cert = nullptr;

    // Create the Input/Output BIO
    certbio = BIO_new(BIO_s_file());

    // Read the certificate
    if (BIO_read_filename(certbio, BrokerSettings::getBrokerCertFile().c_str()) != 1 ||
        !(cert = PEM_read_bio_X509(certbio, nullptr, 0, nullptr)))
    {
        SL_START << "Error loading cert into memory" << SL_ERROR_END;
    }
    else
    {
        // Get the extension data
        int crit = -1;  // Not used
        int idx = -1;
        ASN1_OCTET_STRING* ext_data = (ASN1_OCTET_STRING*)X509_get_ext_d2i(cert, asn1nid, &crit, &idx);
        if (ext_data)
        {
            const unsigned char* data = ASN1_STRING_get0_data(ext_data);
            int length = ASN1_STRING_length(ext_data);

            if (data && length > 0)
            {
                retVal.assign((const char*)data, length);
            }

            ASN1_OCTET_STRING_free(ext_data);
        }
    }

    X509_free(cert);
    BIO_free_all(certbio);

    return retVal;
}

/** {@inheritDoc} */
string BrokerCertsService::determineBrokerTenantGuid() const
{
    if (!checkFilesExist())
    {
        SL_START << "Unable to determine broker Tenant GUID, cert files don't exist" << SL_ERROR_END;
        return "";
    }

    return lookupCertExtension(m_tenantGuidNid);
}

/** {@inheritDoc} */
string BrokerCertsService::determineBrokerGuid() const
{
    if (!checkFilesExist())
    {
        SL_START << "Unable to determine broker GUID, cert files don't exist" << SL_ERROR_END;
        return "";
    }

    return lookupCertExtension(m_clientGuidNid);
}

/** {@inheritDoc} */
bool BrokerCertsService::checkFilesExist() const
{
    return (
        FileUtil::fileExists(BrokerSettings::getBrokerPrivateKeyFile()) &&
        FileUtil::fileExists(BrokerSettings::getBrokerCertFile()) &&
        FileUtil::fileExists(BrokerSettings::getBrokerCertChainFile()) &&
        FileUtil::fileExists(BrokerSettings::getClientCertChainFile())
    );
}
