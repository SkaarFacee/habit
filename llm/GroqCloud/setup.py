from config.question_model import ProviderQuestions
from config.constants import GROQ_API_LABEL,GROQ_MODEL_LABEL
from llm.base_provider import ProviderQuestionClass




class GroqCloudQuestions(ProviderQuestionClass):
    @staticmethod
    def get_questions():
        questions=[
            ProviderQuestions(question='Enter your GroqCloud API key',default_answer='',choice=False,label=GROQ_API_LABEL),
            ProviderQuestions(question='What model do you want to use',
                                default_answer=[
                                    'meta-llama/llama-4-scout-17b-16e-instruct',
                                    'qwen/qwen3-32b',
                                    'openai/gpt-oss-120b',
                                    'llama-3.3-70b-versatile'
                                    ],choice=True,label=GROQ_MODEL_LABEL)
        ]
        return questions