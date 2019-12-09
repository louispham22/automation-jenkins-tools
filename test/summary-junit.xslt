<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" 
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" version="1.0" indent="yes" encoding="utf-8" standalone="no" cdata-section-elements="system-err system-out" />
	
	<xsl:template match="/stage">
		<testsuites name="" disabled="{@skipped}" errors="0" failures="{@failed}" tests="{@total}">
			<testsuite name="{@name}" tests="{@total}" errors="0" failures="{@failed}" hostname="localhost" disabled="{@unstable + @skipped}" skipped="{@triaged}">
				<xsl:apply-templates select="results"/>
			</testsuite>
		</testsuites>
	</xsl:template>
	
	<xsl:template match="failed/test">
		<testcase name="{@name}" classname="{@name}" time="{@duration}">
			<xsl:choose>
				<xsl:when test="count(bug) > 0">
					<failure message="Case marked as a bug is passing">Bugs:<xsl:for-each select="bug"> http://pomine/issues/<xsl:value-of select="@value"/></xsl:for-each></failure>
				</xsl:when>
				<xsl:otherwise>
					<failure message="Test case failed"><xsl:value-of select="reason"/></failure>
				</xsl:otherwise>
			</xsl:choose>
			<system-out/>
			<system-err><xsl:value-of select="reason"/></system-err>
		</testcase>
	</xsl:template>

	<xsl:template match="unstable/test">
		<testcase name="{@name}" classname="{@name}" time="{@duration}">
			<skipped/>
			<system-out>Test case is unstable</system-out>
			<system-err><xsl:value-of select="reason"/></system-err>
		</testcase>
	</xsl:template>

	<xsl:template match="triaged/test">
		<testcase name="{@name}" classname="{@name}" time="{@duration}">
			<skipped/>
			<system-out>Test case failing. Triaged. Known issue. Registered tickets:
				<xsl:for-each select="bug"> http://pomine/issues/<xsl:value-of select="@value"/></xsl:for-each>
			</system-out>
			<system-err/>
		</testcase>
	</xsl:template>

	<xsl:template match="passed/test">
		<testcase name="{@name}" classname="{@name}" time="{@duration}">
			<system-out/>
			<system-err/>
		</testcase>
	</xsl:template>
</xsl:stylesheet>
