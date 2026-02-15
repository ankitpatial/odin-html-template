package ohtml

// Error_Kind enumerates all error categories across the template engine.
Error_Kind :: enum {
	None,
	// Lexer errors
	Unexpected_EOF,
	Bad_Character,
	Unterminated_String,
	Unterminated_Raw_String,
	Unterminated_Comment,
	Unterminated_Char_Constant,
	Bad_Number,
	Unclosed_Action,
	Unclosed_Left_Paren,
	Unexpected_Right_Paren,
	Comment_Ends_Before_Closing_Delim,
	Expected_Colon_Equals,
	// Parser errors
	Unexpected_Token,
	Missing_End,
	Missing_Value,
	Undefined_Variable,
	Undefined_Function,
	Undefined_Template,
	Bad_Pipeline,
	Empty_Command,
	Branch_In_Wrong_Context,
	Too_Many_Decls,
	Max_Paren_Depth,
	Unexpected_EOF_In_Parse,
	// Execution errors
	Not_A_Function,
	Wrong_Arg_Count,
	Wrong_Arg_Type,
	Index_Out_Of_Range,
	Cant_Index,
	Nil_Pointer,
	Cant_Call,
	Not_Iterable,
	Max_Depth_Exceeded,
	Execution_Failed,
	Incomplete_Template,
	Write_Error,
	Break_Signal, // internal: range break control flow
	Continue_Signal, // internal: range continue control flow
	Bad_Comparison_Type,
	No_Comparison,
	// Escape errors
	Bad_Context,
	Predefined_Escaper_Called,
	Ends_In_Unsafe_Context,
}

// Error represents a template engine error with location information.
Error :: struct {
	kind: Error_Kind,
	msg:  string,
	name: string, // template name
	line: int, // line number (1-based)
}
