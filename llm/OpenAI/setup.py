from config.question_model import ProviderQuestions
from llm.base_provider import ProviderQuestionClass



class OpenAIQuestions(ProviderQuestionClass):
    @staticmethod
    def get_questions():
        questions=[
            ProviderQuestions(question='Enter your OpenAI API key',default_answer='',choice=False,label='OPEN_API_KEY'),
            ProviderQuestions(question='What model do you want to use',default_answer=['gpt-4o', 'gpt-3.5'],choice=True,label='OPENAI_MODEL')
        ]
        return questions
    


    