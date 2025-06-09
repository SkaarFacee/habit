import os.path
import pickle
import argparse

from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request

# If modifying these SCOPES, delete the token.pickle file.
SCOPES = ['https://www.googleapis.com/auth/tasks.readonly']
LIST_TRACKER='tracker.txt'

def authenticate_google_tasks():
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

def list_google_tasks(tracked_titles):
    creds = authenticate_google_tasks()
    service = build('tasks', 'v1', credentials=creds)

    tasklists = service.tasklists().list(maxResults=10).execute()
    items = tasklists.get('items', [])
    flag=True

    tasks_info={}

    if not items:
        print('No task lists found.')
        return
    
    
    for tasklist in items:
        if tasklist['title'].strip() in tracked_titles:
            flag=False
            tasks = service.tasks().list(tasklist=tasklist['id']).execute()
            task_items = tasks.get('items', [])
            # if not task_items:
            #     print(' No tasks found.')
            tasks_info[tasklist['title'].strip()]=[
            {
                'title':task.get('title', 'No Title'),
                'status':task.get('status', 'unknown'),
                'due':task.get('due', 'No due date')

            } for task in task_items]

    if flag: 
        print(tracked_titles)
        print('Check the task title. This is case senstive')
    else:
        return tasks_info
    


def load_list():
    if not os.path.exists(LIST_TRACKER):
        with open(LIST_TRACKER,'w') as f: 
            pass
        print('Local file is created')
    return 

def read_local_list():
    with open(LIST_TRACKER,'r') as f:
        all_lines=f.readlines()
    titles = set([line.strip() for line in all_lines])
    return titles

def add_new_tracker(list_name):
    if list_name not in read_local_list():
        with open(LIST_TRACKER,'a') as f: 
            f.write(list_name+'\n')
        return True
            
    else :
        print('List is already being tracked')
        return False

            
if __name__ == '__main__':
    load_list()
    parser = argparse.ArgumentParser(description="CLI app to access Google Tasks")
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
    print(args)

    if args.add:
        if add_new_tracker(args.add):
            print(f"Added list: {args.add}")
            
    if args.list:
        print(read_local_list())
    if not args.list:
        titles=read_local_list()
        print(list_google_tasks(titles))
