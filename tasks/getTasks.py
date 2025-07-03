from config.constants import LIST_TRACKER,SCOPES,GOOGLE_CRED,LOCAL_CRED
from views.tasks_view import TaskView
from views.setup_view import SetupView

import pickle
import os
import json
from datetime import datetime
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from concurrent.futures import ThreadPoolExecutor, as_completed


class TrackerProvider:
    def __init__(self):
        creds = None
        if os.path.exists(LOCAL_CRED):
            with open(LOCAL_CRED, 'rb') as token:
                creds = pickle.load(token)

        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(
                    GOOGLE_CRED, SCOPES)
                creds = flow.run_local_server(port=0)

            with open(LOCAL_CRED, 'wb') as token:
                pickle.dump(creds, token)

        self.creds=creds

    def read_local_list(self):
        if not os.path.exists(LIST_TRACKER):
            name=SetupView.ask_first_list()
            with open(LIST_TRACKER, 'w') as f:
                json.dump({"lists": [name]}, f)
        
        with open(LIST_TRACKER, 'r+') as f: 
            if os.fstat(f.fileno()).st_size == 0:
                f.write(json.dumps({"lists": []}))
                f.seek(0)
            data = json.load(f)
        titles = set(data.get('lists', []))
        return titles

    def add_new_tracker(self,list_name):
        current_lists = self.read_local_list()
        if list_name not in current_lists:
            current_lists.add(list_name)
            with open(LIST_TRACKER,'w') as f:
                json.dump({'lists': list(current_lists)}, f, indent=2)
            return True
        else :
            TaskView.list_already_tracked_view()
            return False

    def authenticate_google_tasks(self):
        creds = None
        if os.path.exists('token.pickle'):
            with open('token.pickle', 'rb') as token:
                creds = pickle.load(token)

        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(
                    'credentials.json', SCOPES)
                creds = flow.run_local_server(port=0)

            with open('token.pickle', 'wb') as token:
                pickle.dump(creds, token)

        return creds

    def list_google_tasks(self,tracked_titles,provider,model):
        service = build('tasks', 'v1', credentials=self.creds)
        tasklists = service.tasklists().list(maxResults=10).execute()
        items = tasklists.get('items', [])
        flag=True

        tasks_info={}

        if not items:
            TaskView.no_tasks_view()
            return
        
        for tasklist in items:
            if tasklist['title'].strip() in tracked_titles:
                flag=False
                tasks = service.tasks().list(tasklist=tasklist['id'],showHidden=True).execute()
                task_items = tasks.get('items', [])
                tasks_info[tasklist['title'].strip()]=self.parallel_process_tasks(task_items,provider,model)

        if flag: 
            TaskView.no_title_view()
        else:
            return tasks_info

    def enrich_task(self,task, provider, model):
        return {
            'title': task.get('title', 'No Title'),
            'status': task.get('status', 'In-progess'),
            'completed': datetime.strptime(task.get('completed', ''), "%Y-%m-%dT%H:%M:%S.%fZ").strftime("%d-%m-%Y") if task.get('completed') else 'Not complete',
            'llm_output': provider.get_category(task.get('title', 'No Title'), model),
        }

    def parallel_process_tasks(self,task_items, provider, model):
        results = []
        with ThreadPoolExecutor() as executor:
            futures = [executor.submit(self.enrich_task, task, provider, model) for task in task_items]
            for future in as_completed(futures):
                results.append(future.result())
        return results
