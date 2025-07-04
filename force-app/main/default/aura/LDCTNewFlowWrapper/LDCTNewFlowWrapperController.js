({
    init : function (cmp) {
        var flow = cmp.find("flow");

        var recordId = cmp.get("v.recordId");
        var inputVariables = [
                { name : "recordId", type : "String", value:recordId },
            ];
        if(recordId) {
            inputVariables.push({ name : "recordId", type : "String", value: recordId });
        }
        
        // initialize for redirect

        flow.startFlow("PLM_LDCT_Create_LDCT_Project", inputVariables);
    },
    handleStatusChange : function (cmp, event) {
        if(event.getParam("status") === "FINISHED") {
            var outputVariables = event.getParam("outputVariables");
            var projectLang=  outputVariables[0].value;
            
            // navigate to screen two
             var recordId = cmp.get("v.recordId");
            var navService = cmp.find("navService");
            var pageReference = {
                type: 'standard__component',
                attributes: {
                    componentName: 'c__pLM_LDCT_Screen2'          
                },
                state: {
                    c__projectId: recordId,
                    c__ProjectLang: projectLang
                }
            };
        
            cmp.set("v.pageReference", pageReference);
            var defaultUrl = "#";
            navService.generateUrl(pageReference)
            .then($A.getCallback(function(url) {
                cmp.set("v.url", url ? url : defaultUrl);
            }), $A.getCallback(function(error) {
                cmp.set("v.url", defaultUrl);
            }));
           // var navService = cmp.find("navService");
           // var pageReference = cmp.get("v.pageReference");
            event.preventDefault();
            navService.navigate(pageReference);

            
            /*
            for(var i = 0; i < outputVariables.length; i++) {
                outputVar = outputVariables[i];
                if(outputVar.name === "recordId") {
                    var urlEvent = $A.get("e.force:navigateToSObject");
                    urlEvent.setParams({
                        "recordId": outputVar.value,
                        "isredirect": "true"
                    });
                    urlEvent.fire();
                    
                }
                location.reload();
            }
            */
            
        }
        
    }

  })