from pathlib import Path
from dotenv import dotenv_values

import os.path
import pickle
import argparse
import ast


from config.setup import Setup
from config.constants import CONFIG_FILE,LIST_TRACKER,SCOPES
from llm import GetProvider
import tasks 
from tasks.getTasks import TrackerProvider
from views.tasks_view import TaskView
from views.setup_view import SetupView
from utils import SaveUtils,Firebase
import json

if __name__ == '__main__':
    firebase_obj=Firebase()
    tracker_data = firebase_obj.get()
    if tracker_data:
        with open(LIST_TRACKER, 'w') as f:
            json.dump(tracker_data, f)
    tasks_obj=TrackerProvider()
    setup_obj=Setup()
    env=dotenv_values(Path.home()/CONFIG_FILE)
    save_utils=SaveUtils()
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
        action='store_true',
        help="Add a list to be tracked"
    )
    parser.add_argument('--version', action='version', version='v0.1.0')
    
    provider,model=GetProvider.return_provider(env.get("MODEL"),env)
    args = parser.parse_args()
    if args.add:
        if tasks_obj.add_new_tracker(SetupView.ask_first_list()):
            pass
    if args.setup:
        setup_obj.setup()         
    if args.list:
        TaskView.display_task_lists(tasks_obj.read_local_list())
    if not args.list:
        titles=tasks_obj.read_local_list()
        response=tasks_obj.list_google_tasks(titles,provider,model)
        # import pickle
        # response=pickle.load(open('./response.pkl','rb'))
        save_utils.save(response,firebase_obj)
        for t in response.keys():
            TaskView.display_tasks(response[t])