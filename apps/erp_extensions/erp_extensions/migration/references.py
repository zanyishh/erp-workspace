"""Exact display labels from original job headers, never inferred from dates."""


def verified_job_reference(record):
    if record.get('namespace') != 'knitpack.job' or record.get('family') != 'job':
        return None
    original = record.get('business_data', {}).get('original_business', {})
    ledger = original.get('job_ledger') or {}
    if not isinstance(ledger, dict):
        return None
    headers = [ledger.get('job')]
    if 'original_saved_job' in original:
        headers.append(original['original_saved_job'])
    for header in headers:
        if (not isinstance(header, dict) or str(header.get('id')) != record.get('native_id')
                or str(header.get('companymas_id')) != record.get('source_company_id')):
            return None
    label = ledger.get('pjobno')
    return label if isinstance(label, str) and label and len(label) <= 4096 and '\x00' not in label else None
