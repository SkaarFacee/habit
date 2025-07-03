import questionary

from config.question_model import ProviderQuestions

class SetupView:
    @staticmethod
    def ask_llm_setup(questions,env_config=None):
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
                    answers.update(SetupView.ask_follow_up_questions(llm_question, env_config))
        return answers
    
    @staticmethod
    def ask_follow_up_questions(llm_questions : ProviderQuestions ,env_config):
        if env_config:
            default_answer=env_config.get(llm_questions.label)
        if llm_questions.choice:
            answer = questionary.select(
                message=llm_questions.question,
                choices=llm_questions.default_answer
            ).ask()
        else:
            answer = questionary.text(
                message=llm_questions.question,
                default=str(default_answer) if env_config else ""
            ).ask()
        return {llm_questions.label:answer}
    
    @staticmethod
    def ask_first_list():
        list_name = questionary.text(
            "📝 Enter the name of the task list you want to track (case-sensitive):"
        ).ask()
        return list_name.strip() if list_name else None


