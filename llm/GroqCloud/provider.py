from llm.base_provider import BaseProvider
from config.constants import DEFAULT_CATEGORIES,SCHEME,GROQ_MODEL_LABEL

class GroqCloudProvider(BaseProvider):
    def __init__(self,api):
        self.categories=DEFAULT_CATEGORIES
        self.api=api

    def get_category(self,task,model):
        import groq
        import json 
        from llm.base_response import BaseResponse

        client = groq.Groq(api_key=self.api)
        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "user",
                    "content": SCHEME.format(categories=self.categories, task=task) + "\n\nRespond in JSON format."
                }
            ],
            response_format={
                "type": "json_object",
                "schema": BaseResponse.model_json_schema()
            }
        )

        result = json.loads(response.choices[0].message.content)
        print(f"Groq response: {result}")
        # Handle both direct response and wrapped 'classified' response
        if 'classified' in result:
            item = result['classified'].pop()
        else:
            item = result
        # Map 'difficulty' to 'diificulty' to match the expected schema (typo preserved for compatibility)
        if 'difficulty' in item:
            item['diificulty'] = item.pop('difficulty')
        return item