from config.constants import LIST_TRACKER,FIREBASE_CRED

import json
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime, MAXYEAR,timedelta

import firebase_admin
from firebase_admin import credentials, firestore

class SaveUtils: 
    def refresh(self):
        self.data=json.load(open(LIST_TRACKER,'r'))
        if 'Tracker' not in self.data.keys():
            self.data['Tracker']={}

    @staticmethod
    def process_list_name(args):
        list_name, items = args
        sorted_items = sorted(
            items,
            key=lambda x: (
                datetime.strptime(x['completed'], '%d-%m-%Y')
                if x['completed'] != 'Not complete'
                else datetime(MAXYEAR, 12, 31)
            )
        )
        grouped_by_date = {}
        for x in sorted_items:
            if x['completed'] != 'Not complete':
                date = x['completed']
                entry = {
                    'title': x['title'],
                    'category': x['llm_output']['category'],
                    'difficulty': x['llm_output']['diificulty']
                }
                grouped_by_date.setdefault(date, []).append(entry)

        formatted_entries = {date: items for date, items in grouped_by_date.items()}
        return {list_name: formatted_entries}

    def save(self, response,firebase_obj):
        self.refresh()
        tracker_entries = []

        with ProcessPoolExecutor() as executor:
            futures = [
                executor.submit(SaveUtils.process_list_name, (list_name, response[list_name]))
                for list_name in self.data['lists']
            ]
            for future in as_completed(futures):
                tracker_entries.append(future.result())
        
        self.create_json(tracker_entries)
        

        for list_name in self.data['lists']:
            tracker = self.data['Tracker'][list_name]
            
            # Sort dates as datetime objects
            dates = sorted(
                tracker.keys(),
                key=lambda x: datetime.strptime(x, '%d-%m-%Y')
            )
            
            # Convert last date to datetime object
            last_date = datetime.strptime(dates[-1], '%d-%m-%Y')
            week_ago = last_date - timedelta(days=7)
            
            for date_key in dates:
                current_date = datetime.strptime(date_key, '%d-%m-%Y')
                
                if current_date > week_ago:
                    tasks = tracker[date_key]
                    not_complete_titles = {
                        x['title']
                        for x in response.get(list_name, [])
                        if x['completed'] == 'Not complete'
                    }
                    tracker[date_key] = [
                        task for task in tasks if task['title'] not in not_complete_titles
                    ]
                    
                    if not tracker[date_key]:
                        print(f'Deleting entery {tracker[date_key]}')
                        del tracker[date_key]
        self.save_json(firebase_obj)


    def create_json(self, tracker_entries):
        tracker = self.data['Tracker']
        for entry in tracker_entries:
            for list_name, dates in entry.items():
                list_data = tracker.setdefault(list_name, {})
                for date_key, tasks in dates.items():
                    date_data = list_data.setdefault(date_key, [])
                    titles_in_date=[x['title'] for x in date_data]
                    for task in tasks:
                        if task['title'] not in titles_in_date:
                            date_data.append(task)



    # BETA VERSION 
    # def create_json(self,tracker_entries):
    #     for entry in tracker_entries:
    #         for list_name in entry.keys():
    #             if list_name not in self.data['Tracker'].keys():
    #                 self.data['Tracker'].update(entry)
    #                 continue 
    #             else: 
    #                 for date_key in entry[list_name].keys():
    #                     if not date_key in self.data['Tracker'][list_name].keys():
    #                         self.data['Tracker'][list_name][date_key]=entry[list_name][date_key]
    #                         continue
    #                     else:
    #                         for task_info in entry[list_name][date_key]:
    #                             if task_info not in self.data['Tracker'][list_name][date_key]:
    #                                 self.data['Tracker'][list_name][date_key].append(task_info)




    def save_json(self,firebase_obj):
        json.dump(self.data,open(LIST_TRACKER,'w'))
        firebase_obj.push(self.data)


class Firebase():
    def __init__(self):
        cred = credentials.Certificate(FIREBASE_CRED)
        firebase_admin.initialize_app(cred)
        self.db = firestore.client()

    def push(self,json):
        doc_ref = self.db.collection("habit").document("tracker")
        doc_ref.set(json)
    
    def get(self):
        doc_ref = self.db.collection("habit").document("tracker")
        doc = doc_ref.get()
        if doc.exists:
            return doc.to_dict()
        else:
            return None