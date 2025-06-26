from pathlib import Path
from dotenv import dotenv_values

import os.path
import pickle
import argparse


from config.setup import Setup
from config.constants import CONFIG_FILE,LIST_TRACKER,SCOPES
from llm import GetProvider
import tasks 
from tasks.temp import TrackerProvider

            
if __name__ == '__main__':
    setup_obj=Setup()
    tasks_obj=TrackerProvider()
    env=dotenv_values(Path.home()/CONFIG_FILE)
    parser = argparse.ArgumentParser(description="CLI app to access Google Tasks")
    parser.add_argument(
        "-s",
        "--setup",
        action='store_true',
        help="Setup based on what you want"
    )
    parser.add_argument(
        "-l",
        "--list",
        action="store_true",
        help="List the user's task list that is being tracked",
    )
    parser.add_argument(
        "-a",
        "--add",
        help="Add a list to be tracked"
    )
    parser.add_argument('--version', action='version', version='v0.1.0')
    
    args = parser.parse_args()
    if args.add:
        if tasks_obj.add_new_tracker(args.add):
            print(f"Added list: {args.add}")
    if args.setup:
        setup_obj.setup()         
    if args.list:
        print(tasks_obj.read_local_list())
    if not args.list:
        titles=tasks_obj.read_local_list()
        print(tasks_obj.list_google_tasks(titles))
    
    
    # # Code that runs the provider
    # provider,model=GetProvider.return_provider(env.get("MODEL"),env)
    # print(model)
    # print(provider.get_category('Coded side project',model))
