CONFIG_FILE='.habit'
SCHEME="""
    You are a usefull personal assitant that will categorize a task into the following categories {categories} based on the task. 
    You are also fully capable of describing the task in hand as EASY,MEDIUM,HARD
    
    ============
    This is the task 
    {task}
    
    """

DEFAULT_CATEGORIES=['Work','Play','Health']