<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" 
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  >
  <xsl:output method="xml" version="1.0" indent="yes" encoding="utf-8" standalone="no" cdata-section-elements="message stack-trace" />
  
  <xsl:template match="message">
    <xsl:copy-of select="."/>
  </xsl:template>
  <xsl:template match="stack-trace">
    <xsl:copy-of select="."/>
  </xsl:template>
  <xsl:template match="reason">
    <xsl:copy-of select="."/>
  </xsl:template>
  <xsl:template match="failure">
    <xsl:copy-of select="."/>
  </xsl:template>

  <xsl:template match="/test-run">
    <test-results name="Result" total="{@testcasecount}" errors="{@testcasecount - @passed - @skipped - @failed}" failures="{@failed}" not-run="{@skipped}" inconclusive="{@inconclusive}" ignored="{@skipped}" skipped="{@skipped}" invalid="0" date="{substring(@start-time, 0, 10)}" time="{substring(@start-time, 11, 8)}">
      <xsl:apply-templates/>
    </test-results>
  </xsl:template>

  <xsl:template match="test-suite">
    <xsl:if test="@result = 'Skipped'">
      <test-suite type="{@type}" name="{@name}" executed="False" result="{@label}">
		<xsl:apply-templates select="properties" />
		<xsl:apply-templates select="failure" />
		<results>
		  <xsl:apply-templates select="test-case" />
		  <xsl:apply-templates select="test-suite" />
		</results>
	  </test-suite>
	</xsl:if>
    <xsl:if test="@result = 'Inconclusive'">
      <test-suite type="{@type}" name="{@name}" executed="False" result="{@result}">
		<xsl:apply-templates select="properties" />
		<xsl:apply-templates select="failure" />
		<results>
		  <xsl:apply-templates select="test-case" />
		  <xsl:apply-templates select="test-suite" />
		</results>
	  </test-suite>
	</xsl:if>
    <xsl:if test="@result = 'Passed'">
      <test-suite type="{@type}" name="{@name}" executed="True" result="Success" success="True" time="{@duration}" asserts="{@asserts}">
		<xsl:apply-templates select="properties" />
		<xsl:apply-templates select="failure" />
		<results>
		  <xsl:apply-templates select="test-case" />
		  <xsl:apply-templates select="test-suite" />
		</results>
	  </test-suite>
	</xsl:if>
    <xsl:if test="@result = 'Failed'">
      <test-suite type="{@type}" name="{@name}" executed="True" result="Error" success="False" time="{@duration}" asserts="{@asserts}">
		<xsl:apply-templates select="properties" />
		<xsl:apply-templates select="failure" />
		<results>
		  <xsl:apply-templates select="test-case" />
		  <xsl:apply-templates select="test-suite" />
		</results>
	  </test-suite>
	</xsl:if>
    <xsl:if test="@result != 'Passed' and @result != 'Skipped' and @result != 'Failed' and @result != 'Inconclusive'">
      <test-suite type="{@type}" name="{@name}" executed="True" result="{@result}" success="False" time="{@duration}" asserts="{@asserts}">
		<xsl:apply-templates select="properties" />
		<xsl:apply-templates select="failure" />
		<results>
		  <xsl:apply-templates select="test-case" />
		  <xsl:apply-templates select="test-suite" />
		</results>
	  </test-suite>
	</xsl:if>
  </xsl:template>

  <xsl:template match="properties">
  	<xsl:if test="property[@name = 'Category']"> 
	  <categories>
        <xsl:for-each select="property[@name = 'Category']">
   	      <category name="{@value}"/>
        </xsl:for-each>
	  </categories>
	</xsl:if>
	<xsl:if test="property[@name != 'Category']"> 
  	  <properties>
	    <xsl:for-each select="property[@name != 'Category']">
  	      <xsl:copy-of select="."/>
	    </xsl:for-each>
	  </properties>
 	</xsl:if>
  </xsl:template>
  
  <xsl:template match="test-case">
	<xsl:if test="@result = 'Skipped'">
	  <test-case name="{@fullname}" executed="False" result="{@label}" >
		<xsl:apply-templates/>
	  </test-case>
	</xsl:if>
	<xsl:if test="@result = 'Inconclusive'">
	  <test-case name="{@fullname}" executed="False" result="{@result}" >
		<xsl:apply-templates/>
	  </test-case>
	</xsl:if>
	<xsl:if test="@result = 'Passed'">
	  <test-case name="{@fullname}" executed="True" result="Success" success="True" time="{@duration}" asserts="{@asserts}" >
		<xsl:apply-templates/>
	  </test-case>
	</xsl:if>
	<xsl:if test="@result = 'Failed'">
	  <test-case name="{@fullname}" executed="True" result="Error" success="False" time="{@duration}" asserts="{@asserts}" >
		<xsl:apply-templates/>
	  </test-case>
	</xsl:if>
	<xsl:if test="@result != 'Passed' and @result != 'Skipped' and @result != 'Failed' and @result != 'Inconclusive'">
	  <test-case name="{@fullname}" executed="True" result="{@result}" success="False" time="{@duration}" asserts="{@asserts}" >
		<xsl:apply-templates/>
	  </test-case>
	</xsl:if>
  </xsl:template>
 
</xsl:stylesheet>

