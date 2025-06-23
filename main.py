from pathlib import Path
from dotenv import dotenv_values

from config.setup import Setup
from config.constants import CONFIG_FILE
from llm import GetProvider


if __name__ =='__main__': 
    setup_obj=Setup()
    env=dotenv_values(Path.home()/CONFIG_FILE)
    provider,model=GetProvider.return_provider(env.get("MODEL"),env)
    print(model)
    print(provider.get_category('Coded side project',model))



