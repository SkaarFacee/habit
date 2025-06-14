from pydantic import BaseModel
from typing import List

class Category(BaseModel):
    category: str
    diificulty: str

class BaseResponse(BaseModel):
    classified:List[Category]
    
