from llm.base_provider import BaseProvider
from config.constants import DEFAULT_CATEGORIES,SCHEME,GEMINI_MODEL_LABEL

class GeminiProvider(BaseProvider):
    def __init__(self,api):
        self.categories=DEFAULT_CATEGORIES
        self.api=api

    def get_category(self,task,model):
        from google import genai
        import json 
        from llm.base_response import BaseResponse


        client = genai.Client(api_key=self.api)
        response = client.models.generate_content(
            model=model,
            contents=SCHEME.format(categories=self.categories,task=task),
            config={
            "response_mime_type": "application/json",
            "response_schema": BaseResponse,
        },
        )

        return json.loads(response.text)['classified'].pop()