from abc import ABC
from llm.base_response import BaseResponse
class BaseProvider(ABC):
    def __init__(self):
        raise NotImplementedError("Subclasses must implement this method")

    def get_category(self, prompt: str, context: str) -> BaseResponse | None:
        raise NotImplementedError("Subclasses must implement this method")


class ProviderQuestionClass(ABC):
    @staticmethod
    def get_questions():
        raise NotImplementedError("Subclasses must implement this method")
