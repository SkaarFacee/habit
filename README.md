# 🛠️ Project Setup Guide

This section outlines the steps required to configure the Google Tasks API and Firebase Storage for this project. Please follow each part carefully to ensure the system functions correctly.
## 📌 Prerequisites

Before you begin, make sure you have the following installed on your machine:

- Python 3.x
- Git
- Access to the Google Cloud Console
- Access to Firebase Console

## 🔧 Setting up Google Tasks API

To enable your app to interact with the Google Tasks API follow the steps below:

### Go to Google Cloud Console
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

## 🔥 Setting up Firebase Storage

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
    - Place this `firebase.json` in the `config` directory,

# ✅ Final Notes

DO NOT commit your credentials.json files to version control (e.g., GitHub). Add them to `.gitignore` to prevent accidental exposure of secrets.

Ensure that the credentials are readable by your application and are kept secure.

These credentials allow access to sensitive resources — treat them as secrets.