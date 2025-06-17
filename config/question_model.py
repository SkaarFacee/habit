from pydantic import BaseModel
from typing import List

class ProviderQuestions(BaseModel):
    question: str
    default_answer:str | List[str]
    choice : bool ='False'
    label : str


class SelectProviderQuestions(BaseModel):
    label:str
    follow_up_questions:List[ProviderQuestions]

class SetupQuestions(BaseModel):
    label : str
    question_prompt: str
    options: List[SelectProviderQuestions]