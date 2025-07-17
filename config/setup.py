import sys
from pathlib import Path
from dotenv import dotenv_values, set_key

from config import config
from config.constants import CONFIG_FILE,GEMINI_MODEL_LABEL,OPENAI_MODEL_LABEL,LIST_TRACKER
from config.question_model import SelectProviderQuestions, SetupQuestions
from llm.Gemini.setup import GeminiQuestions
from llm.OpenAI.setup import OpenAIQuestions
from tasks.getTasks import TrackerProvider
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
        # Runs if config and tracker is not there 
        if not (config.config_path.exists() and Path(LIST_TRACKER).exists()):
            if config.config_path.exists():
                old_config=dotenv_values(Path.home()/CONFIG_FILE)
            else:
                old_config=None
            config_data = SetupView.ask_llm_setup(self.questions,old_config)
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

        