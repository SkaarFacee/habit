from llm.Gemini.provider import GeminiProvider
from llm.OpenAI.provider import OpenAIProvider
from config.constants import GEMINI_API_LABEL,OPENAI_API_LABEL,GEMINI_MODEL_LABEL,OPENAI_MODEL_LABEL

class GetProvider:
    @staticmethod
    def return_provider(model,env):
        if model== GEMINI_MODEL_LABEL:
            return (GeminiProvider(env.get(GEMINI_API_LABEL)),env.get(GEMINI_MODEL_LABEL))
        elif model ==OPENAI_MODEL_LABEL:
            return (OpenAIProvider(env.get(OPENAI_API_LABEL)),OPENAI_MODEL_LABEL)
        else:
            raise ValueError(f"Unsupported model: {model}")
