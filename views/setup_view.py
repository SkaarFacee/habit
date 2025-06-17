import questionary
from rich import print as rprint

from config.question_model import ProviderQuestions

# ProviderQuestions(question='Enter your Gemini API key',default_answer='',choice=False),

class SetupView:
    @staticmethod
    def ask_llm_setup(questions):
        answers={}
        for question in questions:
            answer = questionary.select(
                "",
                choices=[choice.label for choice in question.options]
            ).ask()
            answers[question.label]=answer
            selected_option = next((option for option in question.options if option.label == answer), None)
            if selected_option and selected_option.follow_up_questions:
                for llm_question in selected_option.follow_up_questions:
                    answers.update(SetupView.ask_follow_up_questions(llm_question, selected_option.label))
        return answers
    
    @staticmethod
    def ask_follow_up_questions(llm_questions, llm_name):
        # If it's a multiple-choice question
        if llm_questions.choice:
            answer = questionary.select(
                message=llm_questions.question,
                choices=llm_questions.default_answer
            ).ask()
        else:
            # If it's a free-text question
            answer = questionary.text(
                message=llm_questions.question,
                default=str(llm_questions.default_answer) or ""
            ).ask()
        return {llm_questions.label:answer}

