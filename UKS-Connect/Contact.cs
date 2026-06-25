using System;
using Microsoft.Xrm.Sdk;
using ReddishGreen_CRM_Helper;

namespace UKS_Connect_Plugin
{
    [CrmPluginRegistration("Create",
    "contact", StageEnum.PostOperation, ExecutionModeEnum.Synchronous,
    "", "UKS_Connect_Plugin.Contact: Create of contact", 1,
    IsolationModeEnum.Sandbox
    // Id is assigned by spkl/Plugin Registration Tool on first registration
    // (run rg_spkl\instrument-plugin-code.bat to write it back into this attribute).
    )]
    public class Contact : IPlugin
    {
        ReddishGreen_CRM_Helper.ReddishGreenHelper helper = null;
        IPluginExecutionContext context = null;
        IOrganizationService service = null;

        public void Execute(IServiceProvider serviceProvider)
        {
            ITracingService tracer = (ITracingService)serviceProvider.GetService(typeof(ITracingService));
            context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            IOrganizationServiceFactory factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            service = factory.CreateOrganizationService(context.UserId);

            try
            {
                switch (context.MessageName)
                {
                    case "Create":
                        helper = new ReddishGreen_CRM_Helper.ReddishGreenHelper(tracer, service, context, this.GetType().Name);
                        helper.Trace("Starting : " + context.MessageName);
                        Create();
                        break;
                    default:
                        throw new InvalidPluginExecutionException("Unsupported context");
                }
            }
            catch (Exception ex)
            {
                helper.Trace(ex.Message);
                throw new InvalidPluginExecutionException(ex.Message);
            }
        }

        public void Create()
        {
            // The newly created contact is the Target image (already has its Id at PostOperation).
            Guid contactId = helper.GetMandatoryAttributeValue<Guid>("contactid");
            helper.Trace("Contact created : " + contactId);

            // TODO: add business logic for Create of contact here.
        }
    }
}
