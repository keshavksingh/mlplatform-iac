import os
import logging
import json
import pyodbc

def init():
    """
    This function is called when the container is initialized/started, typically after create/update of the deployment.
    You can write the logic here to perform init operations like caching the model in memory
    """
    global cursor

    cnxn = pyodbc.connect("Driver={ODBC Driver 18 for SQL Server};"
                            "Server=<>.database.windows.net;"
                            "Database=<>;"
                            "uid=<>;pwd=<>;")

    cursor = cnxn.cursor()
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
