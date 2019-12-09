package porters.automation.logging.filter;

import java.util.Optional;
import java.util.logging.Filter;
import java.util.logging.LogManager;
import java.util.logging.LogRecord;
import java.util.regex.Pattern;

/**
 * Simple regular expression filter.
 * 
 * Anything that does not match expression is not loggable.
 * 
 * @author arwyn.hainsworth@porters.jp
 *
 */
public class RegExpFilter implements Filter
{
	private Pattern pattern;
	
	/**
	 * Default constructor
	 */
	public RegExpFilter()
	{
		pattern = Pattern.compile(getProperty("pattern", ".*"));
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
		return pattern.matcher(record.getMessage()).matches();
	}

}
