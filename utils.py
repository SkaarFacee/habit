from config.constants import LIST_TRACKER

import json
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime, MAXYEAR

class SaveUtils: 
    def __init__(self):
        self.refresh()


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

    def save(self, response):
        self.refresh()
        tracker_entries = []

        with ProcessPoolExecutor() as executor:
            futures = [
                executor.submit(SaveUtils.process_list_name, (list_name, response[list_name]))
                for list_name in self.data['lists']
            ]
            for future in as_completed(futures):
                tracker_entries.append(future.result())
        

        for entry in tracker_entries:
            for list_name in entry.keys():
                if list_name not in self.data['Tracker'].keys():
                    ('List not found in tracker')
                    self.data['Tracker'].update(entry)
                else: 
                    for date_key in entry[list_name].keys():
                        if not date_key in self.data['Tracker'][list_name].keys():
                            self.data['Tracker'][list_name][date_key]=[task_info]
                        else:
                            for task_info in entry[list_name][date_key]:
                                if task_info not in self.data['Tracker'][list_name][date_key]:
                                    self.data['Tracker'][list_name][date_key].append(task_info)
        grouped_by_date = {}

        for list_name in self.data['lists']:
            for date_key in self.data['Tracker'][list_name].keys():
                for tasks in self.data['Tracker'][list_name][date_key]:
                    for x in response[list_name]:
                        if x['completed'] == 'Not complete' :
                                if x['title']==tasks['title']:
                                    del tasks
        self.save_json()


    def save_json(self):
        json.dump(self.data,open(LIST_TRACKER,'w'))
