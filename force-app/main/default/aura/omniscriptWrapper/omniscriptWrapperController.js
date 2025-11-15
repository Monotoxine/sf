({
    handleComplete : function(component, event, helper) {
        console.log('✅ OmniScript completed in Aura');
        var eventDetail = event.getParam('detail');
        console.log('Event detail:', eventDetail);

        // Dispatch window event for LWC to listen
        var customEvent = new CustomEvent('omniscriptcomplete', {
            detail: eventDetail,
            bubbles: true,
            composed: true
        });
        window.dispatchEvent(customEvent);

        console.log('✅ Window event dispatched: omniscriptcomplete');
    },

    handleError : function(component, event, helper) {
        console.error('❌ OmniScript error in Aura');
        var eventDetail = event.getParam('detail');
        console.error('Error detail:', eventDetail);

        // Dispatch window error event for LWC to listen
        var customEvent = new CustomEvent('omniscripterror', {
            detail: eventDetail,
            bubbles: true,
            composed: true
        });
        window.dispatchEvent(customEvent);

        console.log('❌ Window event dispatched: omniscripterror');
    }
})
