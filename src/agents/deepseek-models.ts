import type { ModelDefinitionConfig } from "../config/types.js";

export const DEEPSEEK_BASE_URL = "https://api.deepseek.com";
export const DEEPSEEK_DEFAULT_MODEL_ID = "deepseek-chat";
export const DEEPSEEK_DEFAULT_MODEL_REF = `deepseek/${DEEPSEEK_DEFAULT_MODEL_ID}`;
export const DEEPSEEK_DEFAULT_COST = {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
};

export const DEEPSEEK_MODEL_CATALOG = [
    {
        id: "deepseek-chat",
        name: "DeepSeek Chat",
        reasoning: false,
        input: ["text"],
        contextWindow: 64000,
        maxTokens: 8192,
    },
    {
        id: "deepseek-reasoner",
        name: "DeepSeek Reasoner (思考模式)",
        reasoning: true,
        input: ["text"],
        contextWindow: 64000,
        maxTokens: 8192,
    },
] as const;

export type DeepSeekCatalogEntry = (typeof DEEPSEEK_MODEL_CATALOG)[number];

export function buildDeepSeekModelDefinition(entry: DeepSeekCatalogEntry): ModelDefinitionConfig {
    return {
        id: entry.id,
        name: entry.name,
        reasoning: entry.reasoning,
        input: [...entry.input],
        cost: DEEPSEEK_DEFAULT_COST,
        contextWindow: entry.contextWindow,
        maxTokens: entry.maxTokens,
    };
}

export function buildDeepSeekProvider() {
    return {
        baseUrl: DEEPSEEK_BASE_URL,
        api: "openai-completions" as const,
        models: DEEPSEEK_MODEL_CATALOG.map(buildDeepSeekModelDefinition),
    };
}
