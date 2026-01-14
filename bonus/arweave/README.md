# Bonus - Arweave Provenance Pipeline

Goal: store immutable provenance records for compute outputs or proofs. The minimal artifact is a JSON payload that includes output hashes and run metadata.

## What to submit

- Script/service that maps: run output -> provenance JSON -> Arweave upload.
- Include the resulting Arweave transaction ID in your submission.

## Local provenance payload

```bash
python3 provenance.py --results ../hard/matmul/results.json --artifact ../hard/matmul/out.bin --out provenance.json
```

This generates a JSON payload with:
- results hash
- artifact hash
- run metadata

## Upload

Use AR.IO Turbo or a standard Arweave gateway. Replace the endpoint and auth with your provider details.

```bash
python3 provenance.py \
  --results ../hard/matmul/results.json \
  --artifact ../hard/matmul/out.bin \
  --endpoint "https://YOUR_TURBO_ENDPOINT" \
  --api-key "YOUR_API_KEY"
```

## Notes

- Amadeus docs mention Turbo bundling via the TypeScript SDK or AR.IO API for high-throughput uploads.
- Store on-chain only the provenance hash when possible, not full data blobs.
