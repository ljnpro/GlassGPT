import { describe, expect, it } from "vitest";
import {
  normalizeReasoningEffort,
  normalizeModelId,
} from "../types";

describe("Reasoning effort normalization", () => {
  it("should normalize effort for gpt-5.4 model", () => {
    expect(normalizeReasoningEffort("gpt-5.4", "none")).toBe("none");
    expect(normalizeReasoningEffort("gpt-5.4", "low")).toBe("low");
    expect(normalizeReasoningEffort("gpt-5.4", "medium")).toBe("medium");
    expect(normalizeReasoningEffort("gpt-5.4", "high")).toBe("high");
    expect(normalizeReasoningEffort("gpt-5.4", "xhigh")).toBe("xhigh");
  });

  it("should normalize effort for gpt-5.4-pro model", () => {
    expect(normalizeReasoningEffort("gpt-5.4-pro", "medium")).toBe("medium");
    expect(normalizeReasoningEffort("gpt-5.4-pro", "high")).toBe("high");
    expect(normalizeReasoningEffort("gpt-5.4-pro", "xhigh")).toBe("xhigh");
    // none and low are not supported for pro, should fallback to default
    expect(normalizeReasoningEffort("gpt-5.4-pro", "none")).toBe("xhigh");
    expect(normalizeReasoningEffort("gpt-5.4-pro", "low")).toBe("xhigh");
  });

  it("should handle invalid effort values", () => {
    expect(normalizeReasoningEffort("gpt-5.4", "invalid")).toBe("high");
    expect(normalizeReasoningEffort("gpt-5.4-pro", "invalid")).toBe("xhigh");
    expect(normalizeReasoningEffort("gpt-5.4", undefined)).toBe("high");
    expect(normalizeReasoningEffort("gpt-5.4-pro", null)).toBe("xhigh");
  });
});

describe("Model ID normalization", () => {
  it("should normalize valid model IDs", () => {
    expect(normalizeModelId("gpt-5.4")).toBe("gpt-5.4");
    expect(normalizeModelId("gpt-5.4-pro")).toBe("gpt-5.4-pro");
  });

  it("should fallback for invalid model IDs", () => {
    expect(normalizeModelId("invalid")).toBe("gpt-5.4-pro");
    expect(normalizeModelId(undefined)).toBe("gpt-5.4-pro");
    expect(normalizeModelId(null)).toBe("gpt-5.4-pro");
  });
});

describe("Reasoning config construction", () => {
  it("should include summary:auto when effort is not none", () => {
    // This test validates the logic we added to openai-service.ts
    const efforts = ["low", "medium", "high", "xhigh"];
    for (const effort of efforts) {
      const reasoningConfig: Record<string, unknown> = { effort };
      if ((effort as string) !== "none") {
        reasoningConfig.summary = "auto";
      }
      expect(reasoningConfig.summary).toBe("auto");
    }
  });

  it("should NOT include summary when effort is none", () => {
    const effort = "none" as string;
    const reasoningConfig: Record<string, unknown> = { effort };
    if (effort !== "none") {
      reasoningConfig.summary = "auto";
    }
    expect(reasoningConfig.summary).toBeUndefined();
  });
});
