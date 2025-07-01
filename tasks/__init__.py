import os 
from config.constants import LIST_TRACKER

def load_list():
    if not os.path.exists(LIST_TRACKER):
        with open(LIST_TRACKER,'w') as f: 
            pass
        print('Local file is created')
    return 

load_list()