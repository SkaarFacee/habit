from rich import print as rprint
from rich.table import Table
class TaskView:
    @staticmethod
    def no_title_view():
        rprint("[bold red]⚠️  Invalid Task Title[/bold red]")
        rprint("[yellow]Please check the task title. It is [bold]case-sensitive[/bold] and must match exactly.[/yellow]")


    @staticmethod
    def no_tasks_view():
        rprint("[bold red]📭  No Tasks Found[/bold red]")
        rprint("[yellow]You don't have any tasks yet. Create one to get started![/yellow]")


    @staticmethod
    def list_already_tracked_view():
        rprint("[bold blue]📌  List Already Tracked[/bold blue]")
        rprint("[yellow]This task list is already being tracked. No further action needed.[/yellow]")

    @staticmethod
    def display_task_lists(titles):
        if not titles:
            rprint("[bold red]📭 No task lists found.[/bold red]")
            return

        table = Table(title="📋 Tracked Task Lists", show_lines=True)
        table.add_column("Index", style="cyan", justify="right")
        table.add_column("Task List Title", style="green", justify="left")

        for idx, title in enumerate(sorted(titles), 1):
            table.add_row(str(idx), title)

        rprint(table)


    @staticmethod
    def display_tasks(task_list):
        if not task_list:
            rprint("[bold red]📭 No tasks found.[/bold red]")
            return

        table = Table(title="✅ Task List", show_lines=True)

        table.add_column("Index", style="cyan", justify="right")
        table.add_column("Title", style="bold green")
        table.add_column("Status", style="magenta")
        table.add_column("Due Date", style="yellow")
        table.add_column("LLM", style="blue")


        for idx, task in enumerate(task_list, 1):
            title = task.get('title', 'No Title')
            status = task.get('status', 'unknown')
            due = task.get('due', 'No due date')
            llm = task.get('llm_ouput', 'No response')
            table.add_row(str(idx), title, status, due,str(llm))

        rprint(table)