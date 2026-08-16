export type Choice = { letter: string; description: string };

export type ParsedChoices = { choices: Choice[]; preamble: string };

export function detectChoices(text: string): ParsedChoices | null {
  const lines = text.split("\n");
  const choices: Choice[] = [];
  let firstChoiceLine = -1;

  // Every A)–Z) line counts, even if they are not contiguous. An A) inside a
  // code block plus a B) fifty lines later still becomes a two-choice prompt
  // with an empty preamble — same as the inlined parser this was extracted from.
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i]!.match(/^(?:>\s*)?\*{0,2}([A-Z])\)\*{0,2}\s+(.*)/);
    if (match && match[1] && match[2]) {
      if (firstChoiceLine === -1) firstChoiceLine = i;
      choices.push({
        letter: match[1],
        description: match[2].replace(/\*+/g, "").trim(),
      });
    }
  }

  if (choices.length < 2) return null;

  const preamble = lines.slice(0, firstChoiceLine).join("\n").trim();
  return { choices, preamble };
}
