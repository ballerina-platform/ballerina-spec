<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:output method="xml" indent="no"/>
<xsl:preserve-space elements="*"/>

<xsl:template match="/">
  <grammar>
    <xsl:text>&#xA;</xsl:text>
    <xsl:for-each select="//pre[@class='grammar']">
      <xsl:copy-of select="node()"/>
      <xsl:text>&#xA;</xsl:text>
    </xsl:for-each>
  </grammar>
</xsl:template>

</xsl:stylesheet>
