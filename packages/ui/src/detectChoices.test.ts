import { describe, expect, it } from "vitest";
import { detectChoices } from "./detectChoices";

describe("detectChoices", () => {
  it("parses lettered choices and preserves the preamble", () => {
    expect(detectChoices([
      "Choose a deployment strategy:",
      "",
      "**A)** Ship immediately",
      "> B) Run a canary first",
      "C) **Wait** for approval",
    ].join("\n"))).toEqual({
      preamble: "Choose a deployment strategy:",
      choices: [
        { letter: "A", description: "Ship immediately" },
        { letter: "B", description: "Run a canary first" },
        { letter: "C", description: "Wait for approval" },
      ],
    });
  });

  it.each([
    "No choices here.",
    "A) Only one choice",
  ])("returns null for non-choice text: %s", (text) => {
    expect(detectChoices(text)).toBeNull();
  });
});
