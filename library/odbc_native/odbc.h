//#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#define LIB_EXPORT __declspec(dllexport)
#else
#define LIB_EXPORT
#endif
#include <windows.h>
#include <sql.h>
#include <sqlext.h>
#include <sqltypes.h>
#include <stdlib.h>
#include <stdbool.h>
	typedef struct {
		char** errors;
		char error_str[2048];
		int num_errors;
	} odbc_errors_t;
	typedef odbc_errors_t* odbc_errors_ptr;
	typedef struct {
		SQLHENV env;
		SQLHDBC dbc;
		char cnx_str[1024];
		odbc_errors_ptr errors;
		bool failed_to_connect;
	} odbc_ctx_t;
	typedef odbc_ctx_t* odbc_ctx_ptr;
	typedef struct {
		char name[1024];
		SQLSMALLINT data_type;
		SQLULEN size;
		SQLSMALLINT decimal_digits;
		SQLSMALLINT nullable;
	} odbc_column_t;
	typedef odbc_column_t* odbc_column_ptr;
	typedef struct {
		SQLHSTMT stmt;
		SQLSMALLINT num_cols;
		odbc_column_ptr *columns;
		odbc_errors_ptr errors;
		void* last;
		bool failed_to_execute;
	} odbc_stmt_t;
	typedef odbc_stmt_t* odbc_stmt_ptr;

	LIB_EXPORT odbc_ctx_ptr odbc_connect(char*);
	LIB_EXPORT char* odbc_get_cnx_str(odbc_ctx_ptr ctx);

	LIB_EXPORT odbc_stmt_ptr odbc_execute(odbc_ctx_ptr, char*);
	LIB_EXPORT odbc_stmt_ptr odbc_stmt_reference(void);
	LIB_EXPORT bool odbc_cnx_failed(odbc_ctx_ptr ctx);
	LIB_EXPORT char* odbc_get_ctx_errors(odbc_ctx_ptr);
	LIB_EXPORT bool odbc_query_failed(odbc_stmt_ptr stmt);
	LIB_EXPORT char* odbc_get_stmt_errors(odbc_stmt_ptr);
	LIB_EXPORT char* odbc_get_column_name(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT SQLSMALLINT odbc_get_column_datatype(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT SQLULEN odbc_get_column_size(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT SQLSMALLINT odbc_get_column_decimal_digits(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT SQLSMALLINT odbc_get_column_nullable(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT int odbc_get_num_cols(odbc_stmt_ptr);
	LIB_EXPORT bool odbc_fetch_next(odbc_stmt_ptr stmt);
	LIB_EXPORT bool odbc_get_column_as_bool(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT char* odbc_get_column_as_string(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT int odbc_get_column_as_int(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT unsigned long int odbc_get_column_as_uint(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT float odbc_get_column_as_float(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT double odbc_get_column_as_double(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT int odbc_get_column_as_unix_timestamp(odbc_stmt_ptr stmt, int i);
	LIB_EXPORT bool odbc_disconnect(odbc_ctx_ptr);
	LIB_EXPORT int test_sql();
#ifdef __cplusplus
}
#endif
