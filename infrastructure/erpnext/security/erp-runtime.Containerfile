# Direct BuildKit assembly is disabled. Use build-runtime-image.py, which guards
# owned VM-root scratch and preserves assets outside the base sites volume.
FROM frappe/erpnext@sha256:32145acc7f699dc598ca141018a95ebf8e56f516d4a0e76beb7287ae68b303b8

RUN exit 1
