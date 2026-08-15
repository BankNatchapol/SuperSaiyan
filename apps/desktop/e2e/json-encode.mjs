const asValue = process.argv[2] === "--value";
const payload = asValue ? process.argv[3] ?? "" : process.argv.slice(2);
process.stdout.write(JSON.stringify(payload));
