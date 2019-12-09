package porters.automation.logging.filter;

import java.util.Optional;
import java.util.logging.Filter;
import java.util.logging.LogManager;
import java.util.logging.LogRecord;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Filter to limit log to SQL Profiler Messges
 * 
 * @author arwyn.hainsworth@porters.jp
 */
public class SQLProfilerMessageFilter implements Filter
{
	private static final Pattern PROFILER = Pattern.compile(".*Profiler Event: \\[(?<event>[^\\]]*)\\].*?at (?<location>[^\\)]*\\)) duration: (?<duration>[^\\,]*), connection-id: (?<connection>[^\\,]*), statement-id: (?<statement>[^\\,]*), resultset-id: (?<resultset>[^\\,]*), message: (?<message>.*)");
	private Pattern message;
	private Pattern event;
	
	/**
	 * Default Constructor
	 */
	public SQLProfilerMessageFilter()
	{
		message = Pattern.compile(getProperty("message", ".*"));
		event = Pattern.compile(getProperty("event", ".*"));
	}
	
	/**
	 * Get property from log manager or return default
	 * 
	 * @param name property name
	 * @param def the default value if property is not set
	 * @return the value
	 */
	private String getProperty(String name, String def)
	{
		return Optional.ofNullable(LogManager.getLogManager().getProperty(getClass().getName() + "." + name)).orElse(def);
	}

	@Override
	public boolean isLoggable(LogRecord record)
	{
		Matcher match = PROFILER.matcher(record.getMessage());
		if (!match.matches())
		{
			return false;
		}
		Matcher eventMatch = event.matcher(match.group("event"));
		if (!eventMatch.matches())
		{
			return false;
		}
		return message.matcher(match.group("message")).matches();
	}

}
