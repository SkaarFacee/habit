from config.question_model import ProviderQuestions
from config.constants import GEMINI_API_LABEL,GEMINI_MODEL_LABEL
from llm.base_provider import ProviderQuestionClass



class GeminiQuestions(ProviderQuestionClass):
    @staticmethod
    def get_questions():
        questions=[
            ProviderQuestions(question='Enter your Gemini API key',default_answer='',choice=False,label=GEMINI_API_LABEL),
            ProviderQuestions(question='What model do you want to use',default_answer=['gemini-2.0-flash', 'gemini-2.5-flash'],choice=True,label=GEMINI_MODEL_LABEL)
        ]
        return questions
    


    