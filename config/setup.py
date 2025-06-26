import sys
from pathlib import Path
from dotenv import dotenv_values, set_key

from config import config
from config.constants import CONFIG_FILE,GEMINI_MODEL_LABEL,OPENAI_MODEL_LABEL
from config.question_model import SelectProviderQuestions, SetupQuestions
from llm.Gemini.setup import GeminiQuestions
from llm.OpenAI.setup import OpenAIQuestions
from views.setup_view import SetupView
class Setup: 
    def __init__(self):
        self.questions=[
            SetupQuestions(
                label='Model',
                question_prompt='Choose which LLM do you want to use',
                options=[
                    SelectProviderQuestions(
                        label=GEMINI_MODEL_LABEL,
                        follow_up_questions=GeminiQuestions.get_questions()
                    ),
                    SelectProviderQuestions(
                        label=OPENAI_MODEL_LABEL,
                        follow_up_questions=OpenAIQuestions.get_questions()
                    )
                ])]
        if not config.config_path.exists():
            config_data = SetupView.ask_llm_setup(self.questions)
            self.save_config(config_data)
            print(f"✅ Saved config to {config.config_path}")


    def setup(self):
        old_config=dotenv_values(Path.home()/CONFIG_FILE)
        config_data = SetupView.ask_llm_setup(self.questions,old_config)
        self.save_config(config_data)
        print(f"✅ Saved config to {config.config_path}")

    def save_config(self, config_data: dict):
        for key, value in config_data.items():
            set_key(str(config.config_path), key.upper(), str(value))

        