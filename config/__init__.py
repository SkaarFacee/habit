from config.constants import CONFIG_FILE
from pathlib import Path
from dotenv import dotenv_values
class CONFIG: 
    def __init__(self):
        self.config_path=Path.home()/CONFIG_FILE
        self.env=dotenv_values(self.config_path)

    @property
    def gemini_api_key(self):
        return self.env.get('GEMINI_API',None)




config=CONFIG()