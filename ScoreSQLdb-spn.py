import os
import logging
import json
import pyodbc
import adal
import struct
from azure.identity import DefaultAzureCredential

def buildSqlConnection(server, database, tenantId, clientId, clientSecret):

    authorityHostUrl = "https://login.microsoftonline.com"
    authority_url = authorityHostUrl + "/" + tenantId
    context = adal.AuthenticationContext(authority_url, api_version=None)
    
    try:
        token = context.acquire_token_with_client_credentials("https://database.windows.net/", clientId, clientSecret)
    except adal.AdalError as e:
        raise Exception("Authentication error: " + str(e))
    
    driver = "{ODBC Driver 18 for SQL Server}"
    conn_str = "DRIVER=" + driver + ";server=" + server + ";database=" + database
    
    try:
        SQL_COPT_SS_ACCESS_TOKEN = 1256
        tokenb = bytes(token["accessToken"], "UTF-8")
        exptoken = b''
        for i in tokenb:
            exptoken += bytes([i])
            exptoken += bytes(1)
        tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
        connection = pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: tokenstruct})
    except pyodbc.Error as e:
        raise Exception("Database connection error: " + str(e))
    
    return connection


def init():
    """
    This function is called when the container is initialized/started, typically after create/update of the deployment.
    You can write the logic here to perform init operations like caching the model in memory
    """
    global cursor
    clientId = "<GetFromKeyVault>"
    clientSecret = "<GetFromKeyVault>"
    tenantId = "<GetFromKeyVault>"
    server = "<GetFromKeyVault>"
    database = "<>"
    connection = buildSqlConnection(server, database, tenantId, clientId, clientSecret)
    cursor = connection.cursor()
    logging.info("Init complete")


def run(input: str):
    rows = []
    cursor.execute("SELECT * FROM <> WITH (NOLOCK) where <> = '"+input+"'")
    
    for row in cursor.fetchall():
        row_dict = dict(zip([column[0] for column in cursor.description], row))
        rows.append(row_dict)
    
    json_result = json.dumps(rows)
    logging.info("Request processed")
    return json_result
