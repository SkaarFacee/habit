# 🚀 Habit Tracker & AI-Powered Task Categorizer

This project helps you track and categorize your Google Tasks using AI. It started as a command-line tool and now includes a **Flutter-based mobile app** to visualize your productivity and habits on the go. It integrates with Google Tasks to fetch your daily activities, leverages Large Language Models (LLMs) to automatically categorize them, and provides a visual heatmap to help you understand your productivity and habits over time.

## 📱 The Habit Tracker App

We now have a sleek and intuitive mobile application built with Flutter that brings your habit tracking to your fingertips. The app provides a beautiful interface to visualize your categorized tasks and gain insights into your daily routines.

**Key Features of the App:**

*   **Stunning Visualizations**: A beautiful, interactive heatmap of your daily activities.
*   **Dynamic Theming**: Dark and light mode support.
*   **Cross-Platform**: Built with Flutter for a consistent experience on both Android and iOS (iOS is WIP).

*(Add screenshots of the app here)*

## ✨ Motivation

In today's fast-paced world, understanding how we spend our time and what types of tasks dominate our days is crucial for personal growth and productivity. This tool aims to provide insights into your daily habits by:

*   **Automating Task Analysis**: Eliminating the manual effort of categorizing tasks.
*   **Visualizing Activity**: Offering a clear, at-a-glance overview of your work, play, and health activities through both a CLI and a mobile app.
*   **Promoting Self-Awareness**: Helping you identify patterns, balance your efforts, and make informed decisions about your time allocation.

## 🌟 Features

*   **Google Tasks Integration**: Seamlessly connects with your Google Tasks account to retrieve your task lists and individual tasks.
*   **AI-Powered Task Categorization**: Utilizes advanced Large Language Models (LLMs) such as Google Gemini (with optional support for OpenAI models) to automatically classify your tasks into predefined categories (e.g., Work, Play, Health) and assign a difficulty level (EASY, MEDIUM, HARD).
*   **Flutter Mobile App**: A dedicated mobile application to visualize your productivity heatmap.
*   **Comprehensive CLI Interface**:
    *   `--setup` (`-s`): Guides you through the initial configuration process.
    *   `--list` (`-l`): Displays all your tracked Google Task lists and tasks.
    *   `--add` (`-a`): Adds new Google Task lists to be tracked.
*   **Persistent Data Storage**: All categorized task data is securely stored in Google Firebase Firestore.

## 🛠️ Tech Stack

*   **Mobile App**: Flutter, Dart
*   **Backend**: Python
*   **Task Management**: Google Tasks API
*   **Artificial Intelligence**: Google Generative AI (Gemini), OpenAI API (optional)
*   **Database**: Google Firebase Firestore
*   **Authentication**: Google OAuth2

## 🚀 Getting Started

### Prerequisites

*   Python 3.x
*   Git
*   A Google Cloud Platform (GCP) account
*   A Firebase project
*   An API key for Google Gemini (or OpenAI, if preferred)
*   Flutter SDK (for mobile app development)

### Installation & Setup

#### Backend (CLI Tool)

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/Skaarfacee/habit.git
    cd habit
    ```

2.  **Install Python dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

3.  **Project Setup (Google & Firebase)**:
    Follow the detailed setup guide below for setting up Google Tasks API and Firebase.

#### Mobile App (Flutter)

1.  **Navigate to the app directory**:
    ```bash
    cd app
    ```

2.  **Install Flutter dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase for the app**:
    *   Follow the FlutterFire documentation to add Firebase to your Flutter app. You will need to place `google-services.json` in `app/android/app/` for Android and `GoogleService-Info.plist` in `app/ios/Runner/` for iOS.

4.  **Run the app**:
    ```bash
    flutter run
    ```

---

#### 🛠️ Project Setup Guide (Backend)

This section outlines the steps required to configure the Google Tasks API and Firebase Storage for this project. Please follow each part carefully to ensure the system functions correctly.
#### 📌 Prerequisites

Before you begin, make sure you have the following installed on your machine:

- Python 3.x
- Git
- Access to the Google Cloud Console
- Access to Firebase Console

#### 🔧 Setting up Google Tasks API

To enable your app to interact with the Google Tasks API follow the steps below:

##### Go to Google Cloud Console
Navigate to: https://console.cloud.google.com

- Create a New Project

    - Click the project dropdown at the top left
    - Select New Project
    - Name your project and click Create

- Enable the Google Tasks API
    - Within your project, go to APIs & Services > Library
    - Search for Google Tasks API
    - Click Enable

- Create OAuth 2.0 Credentials
    - Navigate to APIs & Services > Credentials
    - Click Create Credentials > OAuth Client ID
    - If prompted, configure the OAuth consent screen first:
        - Set User Type to External (unless otherwise required)
        - Fill in required fields (e.g., App name, Support email)
        - Save and continue through the scopes section (no changes needed for now)
        - Add test users if necessary (usually your own email)

        - Then, continue creating credentials:
            > Choose Application Type: Desktop App <br>
            > Name it (e.g., My Tasks Client) <br>
            > Click Create <br>
        Click Download JSON to get your `credentials.json` file

- Save the File
    - Place the downloaded `credentials.json` in the `config ` directory of the project

#### 🔥 Setting up Firebase Storage

To use Firebase for file storage, follow these steps:

- Go to Firebase Console
    - Visit: https://console.firebase.google.com

- Create or Select a Project
    - Click Add Project or select an existing one
    - Follow the prompts to configure the project
- Enable Firebase Storage
    - In the left sidebar, go to Build > Storage
    - Click Get Started and configure rules as needed
    - Wait for the default storage bucket to be set up

- Generate Admin SDK Credentials
    - Go to Project Settings > Service Accounts
    - Click Generate New Private Key
    - This will download a `firebase.json` file containing your Firebase Admin SDK credentials
- Save the File
    - Place this `firebase.json` in the `config` directory

#### **LLM API Key Setup**:

*   Add your Gemini API key (or OpenAI API key) when prompted while running the app

#### **Initial Application Setup**:
Run the setup command to initialize the application and authenticate with Google Tasks:
    ```bash
    python main.py --setup
    ```

## 💡 Usage

### Command-Line Interface (CLI)

*   **Run the setup wizard**:
    ```bash
    python main.py --setup
    ```
*   **List your tracked Google Task lists and tasks**:
    ```bash
    python main.py --list
    ```
*   **Add a new Google Task list to be tracked**:
    ```bash
    python main.py --add
    ```
    You will be prompted to enter the name of the task list.


## 📂 Project Structure

```
.
├── app/                    # Flutter mobile application
│   ├── lib/                  # Main application source code
│   ├── android/              # Android specific files
│   ├── ios/                  # iOS specific files
│   └── pubspec.yaml          # Flutter dependencies
├── config/                 # Configuration files, constants, API credentials
│   ├── constants.py        # Defines constants like API labels, categories, file paths
│   ├── credentials.json    # Google Tasks API credentials (user-provided)
│   ├── firebase.json       # Firebase Admin SDK credentials (user-provided)
│   ├── tracker.json        # Stores names of Google Task lists being tracked
│   └── ...
├── llm/                    # Large Language Model (LLM) integration
│   ├── base_provider.py    # Base class for LLM providers
│   ├── base_response.py    # Base class for LLM response schema
│   ├── Gemini/             # Gemini LLM specific implementation
│   │   └── provider.py
│   └── OpenAI/             # OpenAI LLM specific implementation (optional)
│       └── provider.py
├── tasks/                  # Logic for Google Tasks interaction and task processing
│   ├── getTasks.py         # Handles Google Tasks API calls, authentication, and task enrichment
│   └── ...
├── views/                  # CLI view components
│   ├── setup_view.py       # CLI views for setup process
│   ├── tasks_view.py       # CLI views for displaying tasks
├── main.py                 # Main application entry point and CLI argument parser
├── utils.py                # Utility functions, including Firebase Firestore integration
├── .gitignore              # Specifies intentionally untracked files to ignore
├── README.md               # This comprehensive guide
└── ...
```

## 🤖 Automating with GitHub Actions

This project includes a GitHub Actions workflow to automatically run the task categorization script on a daily schedule. To enable this, you need to configure the following secrets in your GitHub repository settings.

### Setting up GitHub Secrets

1.  **Navigate to your GitHub repository.**
2.  Go to **Settings** > **Secrets and variables** > **Actions**.
3.  Click **New repository secret** for each of the secrets below.

#### Required Secrets

*   `CREDENTIALS_JSON`:
    *   **Content**: The base64 encoded content of your `credentials.json` file.
    *   **How to get it**:
        1. Run the following command in your terminal: `base64 -i config/credentials.json`
        2. Copy the entire output.
        3. In your GitHub repository, go to **Settings** > **Secrets and variables** > **Actions**, click **New repository secret**, name it `CREDENTIALS_JSON`, and paste the copied output into the "Value" field.

*   `FIREBASE_JSON`:
    *   **Content**: The base64 encoded content of your `firebase.json` file.
    *   **How to get it**:
        1. Run the following command in your terminal: `base64 -i config/firebase.json`
        2. Copy the entire output.
        3. In your GitHub repository, create a new secret named `FIREBASE_JSON` and paste the copied output into the "Value" field.

*   `TOKEN_PICKLE`:
    *   **Content**: The base64 encoded content of your `token.pickle` file.
    *   **How to get it**:
        1. This file is generated after you run the application for the first time with the `--setup` flag and authenticate with your Google account.
        2. Once the `config/token.pickle` file is created, run the following command: `base64 -i config/token.pickle`
        3. Copy the entire output.
        4. In your GitHub repository, create a new secret named `TOKEN_PICKLE` and paste the copied output into the "Value" field.

*   `GEMINI_API_KEY`:
    *   **Content**: Your API key for the Google Gemini.
    *   **How to get it**:
        1. In your GitHub repository, create a new secret named `GEMINI_API_KEY`.
        2. Paste your actual API key for Gemini into the "Value" field.

The workflow is now configured to use the Gemini model (`gemini-2.0-flash`) by default. You only need to provide the API key.

**Note on `tracker.json`**: You no longer need to provide `tracker.json` as a secret. The workflow now automatically fetches the latest task data from Firebase at the beginning of each run and pushes the updated data back at the end. This ensures your tracked tasks are always in sync.

Once these secrets are configured, the GitHub Action will run automatically every day at midnight, keeping your task data up-to-date.

## 🤝 Contributing

Contributions are welcome! If you have suggestions for improvements, new features, or bug fixes, please feel free to open an issue or submit a pull request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.


## TO-DO
- [x] Finalize on whether a android widget or html would be better
- [ ] Build the OpenAI and ollama provider