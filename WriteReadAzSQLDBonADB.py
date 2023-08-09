#https://learn.microsoft.com/en-us/sql/connect/spark/connector?view=sql-server-ver16
#Install adal, and maven co-ordinates for "Spark 3.1.x compatible connector"	"com.microsoft.azure:spark-mssql-connector_2.12:1.2.0"
#Use ADB Cluster with Spark 3.1.X
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType
spark = SparkSession.builder.appName("EmptyDataFrameExample").getOrCreate()
schema = StructType([
    StructField("VisitorID", StringType(), False),  # Not nullable
    StructField("ContentId", StringType(), True),       # Nullable
    StructField("id", StringType(), True)           # Nullable
])
df = spark.createDataFrame([], schema)

from adal import AuthenticationContext
from pyspark.sql import SparkSession
SQL_READ_SPN = <"">
SQL_READ_SPNKEY = <"">
TenantId = <"">
authority = "https://login.microsoftonline.com/" + TenantId
resourceAppIdURI = "https://database.windows.net/"
context = AuthenticationContext(authority)
token = context.acquire_token_with_client_credentials(resourceAppIdURI,SQL_READ_SPN,SQL_READ_SPNKEY)
access_token = token["accessToken"]
SQL_SERVER_INSTANCE = "jdbc:sqlserver://<ServerName>.database.windows.net:1433;databaseName=<DBName>;loginTimeout=18000"
Query = "SELECT * FROM [<TableName>]"

pySql = SparkSession.builder.appName("AzSQLPySpark").getOrCreate()

df = pySql.read \
    .format("com.microsoft.sqlserver.jdbc.spark") \
    .option("url", SQL_SERVER_INSTANCE) \
    .option("query", Query) \
    .option("accessToken", access_token) \
    .option("encrypt", "true") \
    .option("hostNameInCertificate", "*.database.windows.net") \
    .option("driver","com.microsoft.sqlserver.jdbc.SQLServerDriver") \
    .load()
display(df)
df = spark.createDataFrame(df.rdd, schema=schema)
#Ensure Column is NOT NULL, Updating Schema of Column
df.printSchema()

table_name = "<TableName>"
df.write \
.format("com.microsoft.sqlserver.jdbc.spark") \
.mode("overwrite") \
.option("truncate","true") \
.option("url", SQL_SERVER_INSTANCE) \
.option("dbtable", table_name) \
.option("accessToken", access_token) \
.option("batchsize", 10000) \
.option("tableLock", "true") \
.option("reliabilityLevel", "BEST_EFFORT") \
.option("driver","com.microsoft.sqlserver.jdbc.SQLServerDriver") \
.save()

## Executing Stored Procedure FROm ADB

SQLServerDataSource = spark._sc._gateway.jvm.com.microsoft.sqlserver.jdbc.SQLServerDataSource
client_id = <"">
client_secret = <"">
datasource = SQLServerDataSource()
datasource.setServerName(f'<Server>.database.windows.net')
datasource.setDatabaseName('<DBName>')
datasource.setAuthentication('ActiveDirectoryServicePrincipal')
datasource.setAADSecurePrincipalId(client_id)
datasource.setAADSecurePrincipalSecret(client_secret)
connection = datasource.getConnection()
statement = connection.createStatement()

activeTablename = '<TableName>'
passiveTablename = 'TableName'
ExecQuery = f"""EXEC dbo.SwapTables @activeTableName = '{activeTablename}',@passiveTableName = '{passiveTablename}'"""
#results = statement.executeQuery(ExecQuery)
#connection = datasource.getConnection()
#statement = connection.createStatement()
#try:
#  results = statement.executeQuery('SELECT name FROM sysusers')
#  while results.next():
#    print(results.getString('name'))
#except:
#  print('oops')
statement.execute(ExecQuery)
