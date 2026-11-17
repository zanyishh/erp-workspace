/* Local regression for CVE-2026-86144; no network requests are performed. */
#include <stdio.h>
#include <string.h>
#include <libxml/parser.h>
#include <libxml/xinclude.h>

static int observed_calls;
static int missing_nonet;

static xmlParserInputPtr observe_loader(const char *url, const char *id,
                                       xmlParserCtxtPtr context) {
    (void)url;
    (void)id;
    observed_calls++;
    if (context == NULL || !(context->options & XML_PARSE_NONET))
        missing_nonet++;
    return NULL; /* Never access the network or filesystem. */
}

int main(void) {
    const char *xml[] = {
        "<doc xmlns:xi='http://www.w3.org/2001/XInclude'><xi:include href='http://security-test.invalid/fixture.xml'/></doc>",
        "<doc xmlns:xi='http://www.w3.org/2001/XInclude'><xi:include parse='text' href='http://security-test.invalid/fixture.txt'/></doc>"
    };
    xmlExternalEntityLoader original = xmlGetExternalEntityLoader();
    xmlSetExternalEntityLoader(observe_loader);
    for (int method = 0; method < 2; method++) {
        for (int mode = 0; mode < 2; mode++) {
            xmlDocPtr doc = xmlReadMemory(xml[mode], (int)strlen(xml[mode]),
                                         "synthetic.xml", NULL, XML_PARSE_NONET);
            if (doc == NULL) return 2;
            if (method == 0) xmlXIncludeProcess(doc);
            else xmlXIncludeProcessTree(xmlDocGetRootElement(doc));
            xmlFreeDoc(doc);
        }
    }
    xmlSetExternalEntityLoader(original);
    xmlCleanupParser();
    printf("loader_calls=%d missing_nonet=%d\n", observed_calls, missing_nonet);
    return observed_calls == 4 && missing_nonet == 0 ? 0 : 1;
}
