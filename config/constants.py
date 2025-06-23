CONFIG_FILE='.habit'
SCHEME="""
    You are a usefull personal assitant that will categorize a task into the following categories {categories} based on the task. 
    You are also fully capable of describing the task in hand as EASY,MEDIUM,HARD
    
    ============
    This is the task 
    {task}
    
    """

DEFAULT_CATEGORIES=['Work','Play','Health']
GEMINI_PROVIDER_MODEL_LABEL='Gemini'
GEMINI_API_LABEL='GEMINI_API_KEY'
GEMINI_MODEL_LABEL='GEMINI_MODEL'


OPENAI_PROVIDER_MODEL_LABEL='OpenAI'
OPENAI_API_LABEL='OPEN_API_KEY'
OPENAI_MODEL_LABEL='OPENAI_MODEL'