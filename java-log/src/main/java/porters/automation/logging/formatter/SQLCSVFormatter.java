package porters.automation.logging.formatter;

import java.util.logging.Formatter;
import java.util.logging.LogRecord;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Simplistic CSV formatter for SQL Profiler messages.
 * 
 * Anything that is not a SQL Profiler message is dropped
 * 
 * @author arwyn.hainsworth@porters.jp
 *
 */
public class SQLCSVFormatter extends Formatter
{
	private static final Pattern PROFILER = Pattern.compile(".*Profiler Event: \\[(?<event>[^\\]]*)\\].*?at (?<location>[^\\)]*\\)) duration: (?<duration>[^\\,]*), connection-id: (?<connection>[^\\,]*), statement-id: (?<statement>[^\\,]*), resultset-id: (?<resultset>[^\\,]*), message: (?<message>.*)");
	
	@Override
	public String format(LogRecord record)
	{
		Matcher match = PROFILER.matcher(record.getMessage());
		if (match.matches())
		{
			StringBuilder builder = new StringBuilder(100);
			writeNum(builder, record.getMillis());
			writeStr(builder, match.group("event"), true);
			writeStr(builder, match.group("location"), true);
			writeStr(builder, match.group("duration"), true);
			writeNum(builder, match.group("connection"));
			writeNum(builder, match.group("statement"));
			writeNum(builder, match.group("resultset"));
			writeStr(builder, match.group("message"), false);
			return builder.toString();
		}
		return "";
	}
	
	/**
	 * Write an escaped string. All whitespace is collapsed.
	 * 
	 * @param builder the string builder
	 * @param data the data to write
	 * @param hasNext true if next column exists
	 */
	private void writeStr(StringBuilder builder, String data, boolean hasNext)
	{
		if (data != null && !data.isEmpty())
		{
			builder.append('"')
				.append(data.replace("\"", "\"\"")
					.replaceAll("[\\s]+", " "))
				.append('"');
		}
		
		builder.append(hasNext ? "," : "\n");
	}
	
	/**
	 * Write numeric (un-escaped) value. next column is assumed to exist
	 * 
	 * @param builder the string builder
	 * @param data the data to write
	 */
	private void writeNum(StringBuilder builder, String data)
	{
		if (data != null && !data.isEmpty())
		{
			builder.append(data);
		}
		builder.append(',');
	}
	
	/**
	 * Write numeric (un-escaped) value. next column is assumed to exist
	 * 
	 * @param builder the string builder
	 * @param data the data to write
	 */
	private void writeNum(StringBuilder builder, long data)
	{
		builder.append(data).append(',');
	}

}
