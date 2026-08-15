export function parseJsonLines(text: string): unknown[] {
  return text.split(/\r?\n/).filter(Boolean).map((line, index) => {
    try {
      return JSON.parse(line);
    } catch {
      throw new Error(`Invalid JSONL at line ${index + 1}: ${line.slice(0, 120)}`);
    }
  });
}
