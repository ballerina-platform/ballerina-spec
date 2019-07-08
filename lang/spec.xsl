<!--
Replace top-level ToC by full ToC.
Also generate hyperlinks from dfn/abbr elements in the grammar.

The source document explicitly numbers the <h2> elements and has a manually
maintained top-level ToC that includes just the <h2> elements. This
transformation replaces this manual ToC by a full ToC and generates section
numbers for all other levels.
-->
<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:output method="html" indent="yes"/>
<xsl:preserve-space elements="*"/>

<xsl:key name="heading" match="h2|h3|h4|h5" use="@id"/>

<xsl:template match="node()">
  <xsl:copy>
    <xsl:copy-of select="@*"/>
    <xsl:apply-templates select="node()"/>
  </xsl:copy>
</xsl:template>

<xsl:template match="pre[@class='grammar']/dfn" priority="1">
  <span class="ntdfn" id="{.}"><xsl:apply-templates/></span>
</xsl:template>

<xsl:template match="pre[@class='grammar']/abbr" priority="1">
  <a href="#{.}"><span class="ntref"><xsl:apply-templates/></span></a>
</xsl:template>

<xsl:template match="section[@class='toc']" priority="1">
  <xsl:copy>
    <xsl:copy-of select="@*|h2"/>
    <ul>
      <xsl:apply-templates mode="toc" select="following-sibling::section"/>
    </ul>
  </xsl:copy>
</xsl:template>

<xsl:template match="h3|h4|h5" priority="1">
  <xsl:copy>
    <xsl:copy-of select="@*"/>
    <xsl:if test="not(@id)">
      <xsl:attribute name="id">
	<xsl:call-template name="gen-id"/>
      </xsl:attribute>
    </xsl:if>
    <xsl:apply-templates select="." mode="number"/>
    <xsl:text> </xsl:text>
    <xsl:apply-templates select="node()"/>
  </xsl:copy>
</xsl:template>

<xsl:template mode="toc" match="section">
  <li>
    <xsl:apply-templates mode="toc" select="h2|h3|h4|h5"/>
    <xsl:if test="section">
      <ul>
	<xsl:apply-templates mode="toc" select="section"/>
      </ul>
    </xsl:if>
  </li>
</xsl:template>

<xsl:template mode="toc" match="h2">
  <!-- Don't include the number in the link. -->
  <!-- This tries to work even if there is markup in the h2. -->
  <xsl:for-each select="text()[1]">
    <xsl:value-of select="substring-before(string(.),' ')"/>
    <xsl:text> </xsl:text>
    <a href="#{../@id}">
      <xsl:value-of select="substring-after(string(.),' ')"/>
      <xsl:copy-of select="following-sibling::node()"/>
    </a>
  </xsl:for-each>
</xsl:template>

<xsl:template mode="toc" match="h3|h4|h5">
  <xsl:apply-templates select="." mode="number"/>
  <xsl:text> </xsl:text>
  <a>
    <xsl:call-template name="href-attr"/>
    <xsl:copy-of select="node()"/>
  </a>
</xsl:template>

<xsl:template name="href-attr">
  <xsl:attribute name="href">
    <xsl:text>#</xsl:text>
    <xsl:choose>
      <xsl:when test="@id">
	<xsl:value-of select="@id"/>
      </xsl:when>
      <xsl:otherwise>
	<xsl:call-template name="gen-id"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:attribute>
</xsl:template>

<xsl:template name="gen-id">
  <xsl:text>section_</xsl:text>
  <xsl:apply-templates mode="number" select="."/>
</xsl:template>

<xsl:template mode="number" match="*">
  <xsl:number level="multiple" count="section[not(@class)]" format="1.1"/>
</xsl:template>

<xsl:template mode="number" match="section[@class='appendix']//*">
  <xsl:number level="multiple"
	      count="section[@class='appendix']|section/section"
	      format="A.1"/>
</xsl:template>

</xsl:stylesheet>
