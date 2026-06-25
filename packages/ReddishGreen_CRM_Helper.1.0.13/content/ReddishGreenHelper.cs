using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Security.Cryptography;
using System.Text;
using System;
using Microsoft.Crm.Sdk.Messages;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Metadata;
using Microsoft.Xrm.Sdk.Query;
using Microsoft.Xrm.Sdk.Metadata.Query;
// test
namespace ReddishGreen_CRM_Helper
{
    public class ReddishGreenHelperContext
    {
        public const int TARGET = 0;
        public const int POSTIMAGE = 1;
        public const int PREIMAGE = 2;
    }

    public class ReddishGreenHelperPostSource
    {
        public const int Auto = 1;
        public const int Manual = 2;
    }

    public class ReddishGreenHelper
    {
        private readonly ITracingService trace;
        public readonly IOrganizationService service;
        private readonly List<Entity> entities = new List<Entity>();
        private readonly string caller;
        public readonly IPluginExecutionContext context;
        public Entity preImage = null;
        public Entity targetImage = null;
        public Entity postImage = null;
        private readonly bool obfuscate;


        public ReddishGreenHelper(ITracingService t, IOrganizationService s, IPluginExecutionContext context, string c = "", bool pre = false, bool target = true, bool post = false, bool obfuscate = false)
        {
            trace = t;
            service = s;
            caller = c;
            this.context = context;
            this.obfuscate = obfuscate;

            if (pre)
            {
                Trace("getting preimage for : " + c);
                preImage = GetContextEntity(context, ReddishGreenHelperContext.PREIMAGE);
            }

            if (target)
            {
                Trace("getting target for : " + c);
                targetImage = GetContextEntity(context, ReddishGreenHelperContext.TARGET);
            }

            if (post)
            {
                Trace("getting post for : " + c);
                postImage = GetContextEntity(context, ReddishGreenHelperContext.POSTIMAGE);
            }

            Trace("helper initialised");
        }

        public void Assign(EntityReference target, EntityReference assignee)
        {
            var req = new AssignRequest();
            req.Assignee = assignee;
            req.Target = target;
            service.Execute(req);
        }

        public void Assign(Entity target, Entity assignee)
        {
            Assign(target.ToEntityReference(), assignee.ToEntityReference());
        }

        public void Assign(EntityReference target, Entity assignee)
        {
            Assign(target, assignee.ToEntityReference());
        }

        public void Assign(Entity target, EntityReference assignee)
        {
            Assign(target.ToEntityReference(), assignee);
        }

        public void RevokeSharedAccess(EntityReference target, EntityReference revokee)
        {
            var revoke = new RevokeAccessRequest();
            revoke.Target = target;
            revoke.Revokee = revokee;
            service.Execute(revoke);
        }

        public T GetValue<T>(Entity entity, string attributeName)
        {
            //get the attribute

            if (entity.Attributes.ContainsKey(attributeName))
            {
                var attr = entity[attributeName];
                if (attr is AliasedValue)
                {
                    return GetAliasedValueValue<T>(entity, attributeName);
                }
                else
                {
                    return entity.GetAttributeValue<T>(attributeName);
                }
            }
            else
            {
                return default(T);
            }

        }

        public string GetStringValue(Entity entity, string attributeName)
        {
            //get the attribute

            if (entity.Attributes.ContainsKey(attributeName))
            {
                var attr = entity[attributeName];
                if (attr is AliasedValue)
                {
                    return GetAliasedValueValue<string>(entity, attributeName);
                }
                else
                {
                    return entity.GetAttributeValue<string>(attributeName);
                }
            }
            else
            {
                return default(string);
            }

        }

        public EntityReference GetEntityReferenceValue(Entity e)
        {
            return new EntityReference(e.LogicalName, e.Id);
        }

        public EntityReference GetEntityReferenceValue()
        {
            return new EntityReference(targetImage.LogicalName, targetImage.Id);
        }

        public EntityReference GetEntityReferenceValue(Entity entity, string attributeName)
        {
            //get the attribute

            if (entity.Attributes.ContainsKey(attributeName))
            {
                var attr = entity[attributeName];
                if (attr is AliasedValue)
                {
                    return GetAliasedValueValue<EntityReference>(entity, attributeName);
                }
                else
                {
                    return entity.GetAttributeValue<EntityReference>(attributeName);
                }
            }
            else
            {
                return default(EntityReference);
            }

        }

        public OptionSetValue GetOptionSetValue(Entity entity, string attributeName)
        {
            //get the attribute

            if (entity.Attributes.ContainsKey(attributeName))
            {
                var attr = entity[attributeName];
                if (attr is AliasedValue)
                {
                    return GetAliasedValueValue<OptionSetValue>(entity, attributeName);
                }
                else
                {
                    return entity.GetAttributeValue<OptionSetValue>(attributeName);
                }
            }
            else
            {
                return default(OptionSetValue);
            }

        }

        public OptionSetValue GetOptionSetValue(string attributeName)
        {
            if (targetImage != null && targetImage.Contains(attributeName))
                return GetOptionSetValue(targetImage, attributeName);

            if (preImage != null)
                return GetOptionSetValue(preImage, attributeName);

            return GetOptionSetValue(targetImage, attributeName);
        }


        public decimal SumMoneyField(IEnumerable<Entity> entities, string fieldName)
        {
            return entities.Where(x => x.Attributes.ContainsKey(fieldName))
                           .Sum(x => this.GetValue<Money>(x, fieldName).Value);
        }

        public T GetAliasedValueValue<T>(Entity entity, string attributeName)
        {
            var attr = entity.GetAttributeValue<AliasedValue>(attributeName);
            if (attr != null)
            {
                return (T)attr.Value;
            }
            else
            {
                return default(T);
            }

        }

        public Entity CloneEntity(Entity entityToClone)
        {
            //does not work in sandbox - use cloneentitysandbox instead
            var earlyBoundSerializer = new DataContractSerializer(typeof(Entity));
            var newEntity = new Entity();
            using (var stream = new MemoryStream())
            {
                // Write the XML to disk.B
                earlyBoundSerializer.WriteObject(stream, entityToClone);
                stream.Position = 0;

                newEntity = (Entity)earlyBoundSerializer.ReadObject(stream);

            }

            return newEntity;

        }

        public Entity CloneEntitySandbox(Entity entityToClone, string newLogicalName = "")
        {
            Entity newEntity;

            if (newLogicalName != string.Empty)
            {
                newEntity = new Entity(newLogicalName);
            }
            else
            {
                newEntity = new Entity(entityToClone.LogicalName);
            }

            var systemAttributes = new List<string>();
            systemAttributes.Add("createdon");
            systemAttributes.Add("createdby");
            systemAttributes.Add("modifiedon");
            systemAttributes.Add("modifiedby");
            systemAttributes.Add("owninguser");
            systemAttributes.Add("owningbusinessunit");
            systemAttributes.Add("organizationid");


            foreach (var attribute in entityToClone.Attributes
                .Where(x => x.Key != entityToClone.LogicalName + "id")
                .Where(x => !systemAttributes.Contains(x.Key)))
            {

                switch (attribute.Value.GetType().Name)
                {
                    case "Money":
                        var m = attribute.Value as Money;
                        newEntity[attribute.Key] = new Money(m.Value);
                        break;
                    case "EntityReference":
                        var er = attribute.Value as EntityReference;
                        newEntity[attribute.Key] = new EntityReference(er.LogicalName, er.Id);
                        break;
                    case "OptionSetValue":
                        var os = attribute.Value as OptionSetValue;
                        newEntity[attribute.Key] = new OptionSetValue(os.Value);
                        break;
                    default:
                        newEntity[attribute.Key] = attribute.Value;
                        break;
                }

            }

            return newEntity;
        }

        public Entity CloneEntitySandbox(Entity entityToClone, List<string> fieldNamesToSkip)
        {
            var e = new Entity(entityToClone.LogicalName);

            foreach (var attr in entityToClone.Attributes)
            {
                if (attr.Key != entityToClone.LogicalName + "id" && !fieldNamesToSkip.Contains(attr.Key))
                {
                    SetAttributeValue(e, attr.Key, attr.Value);
                }
            }

            return e;
        }

        public T CloneEntitySandbox<T>(T entityToClone) where T : Entity, new()
        {
            var e = new T();
            e.LogicalName = entityToClone.LogicalName;

            foreach (var attr in entityToClone.Attributes)
            {
                if (attr.Key != entityToClone.LogicalName + "id")
                {
                    SetAttributeValue(e, attr.Key, attr.Value);
                }
            }

            foreach (var f in entityToClone.FormattedValues)
            {
                e.FormattedValues.Add(f.Key, f.Value);
            }


            return e;
        }

        public string GetFormattedValue(Entity entity, string attributeName)
        {
            if (entity.Attributes.Contains(attributeName))
            {
                return entity.FormattedValues[attributeName];
            }
            else
            {
                return null;
            }

        }



        public T GetAttributeValue<T>(Entity entity, string attributeName, Entity image)
        {
            if (entity.Attributes.Contains(attributeName))
            {
                return entity.GetAttributeValue<T>(attributeName);
            }
            else if (image != null && image.Attributes.Contains(attributeName))
            {
                return image.GetAttributeValue<T>(attributeName);
            }
            else
            {
                return default(T);
            }
        }

        public void SetAttributeValue(Entity entity, string attributeName, object attributeValue)
        {
            if (entity.Attributes.Contains(attributeName))
            {
                entity.Attributes[attributeName] = attributeValue;
            }
            else
            {
                entity.Attributes.Add(attributeName, attributeValue);
            }
        }

        public string SerializeToString(Entity entity)
        {
            string result = string.Empty;
            using (MemoryStream memStm = new MemoryStream())
            {
                var serializer = new DataContractSerializer(typeof(Entity));
                serializer.WriteObject(memStm, entity);

                memStm.Seek(0, SeekOrigin.Begin);
                result = new StreamReader(memStm).ReadToEnd();
            }

            return result;
        }


        public EntityMetadata RetrieveEntityMetadata(string logicalName)
        {
            try
            {
                var request = new RetrieveEntityRequest
                {
                    LogicalName = logicalName,
                    EntityFilters = EntityFilters.Attributes,
                    RetrieveAsIfPublished = true

                };

                var response = (RetrieveEntityResponse)service.Execute(request);

                return response.EntityMetadata;
            }
            catch (Exception error)
            {
                throw new Exception("RetrieveAuditHistory Error while retrieving entity metadata: " + error.StackTrace);
            }
        }


        public AttributeMetadata RetrieveAttributeMetadata(string entityName, string attributeName)
        {
            try
            {
                var attributeRequest = new RetrieveAttributeRequest
                {
                    EntityLogicalName = entityName,
                    LogicalName = attributeName,
                    RetrieveAsIfPublished = true
                };

                // Execute the request
                var attributeResponse =
                    (RetrieveAttributeResponse)service.Execute(attributeRequest);

                return attributeResponse.AttributeMetadata;
            }
            catch (Exception error)
            {
                throw new Exception("RetrieveAuditHistory Error while retrieving attribute metadata: " + error);
            }
        }


        public string RetrieveTargetName(string entityName, Guid entityId, string primaryAttributeName)
        {
            try
            {
                var record = service.Retrieve(entityName, entityId, new ColumnSet(primaryAttributeName));
                return record.GetAttributeValue<string>(primaryAttributeName);
            }
            catch (Exception error)
            {
                throw new Exception("RetrieveAuditHistory Error while retrieving name for one record: " + error);
            }
        }


        public void ExecuteMultiple(IEnumerable<OrganizationRequest> requests)
        {
            var req = new ExecuteMultipleRequest();
            req.Requests = new OrganizationRequestCollection();
            req.Settings = new ExecuteMultipleSettings();
            req.Settings.ContinueOnError = false;
            req.Settings.ReturnResponses = false;

            req.Requests.AddRange(requests);

            service.Execute(req);
        }



        public void SetStatus(EntityReference entity, int state, int status)
        {
            var req = new SetStateRequest();
            req.EntityMoniker = entity;
            req.State = new OptionSetValue(state);
            req.Status = new OptionSetValue(status);
            service.Execute(req);
        }

        public Entity GetEntityByName(string entityName, string nameFieldName, string nameValue)
        {
            var q = new QueryExpression(entityName);
            q.ColumnSet = new ColumnSet(true);
            AddCriteria(q, nameFieldName, nameValue);

            return GetMultiple(q).SingleOrDefault();
        }

        public Entity GetEntity(string entityName, Guid id)
        {
            return service.Retrieve(entityName, id, new ColumnSet(true));
        }

        public Entity GetEntity(string entityName, Guid id, string[] columns)
        {
            return service.Retrieve(entityName, id, new ColumnSet(columns));
        }
        public Entity GetEntity(string entityName, Guid id, ColumnSet columns)
        {
            return service.Retrieve(entityName, id, columns);
        }

        public Entity GetEntity(string field)
        {
            EntityReference entity = GetMandatoryAttributeValue<EntityReference>(field);
            return service.Retrieve(entity.LogicalName, entity.Id, new ColumnSet(true));
        }

        public Entity GetEntityOptional(string field)
        {
            if (!ContainsField(field))
                return null;

            EntityReference entity = GetMandatoryAttributeValue<EntityReference>(field);
            return service.Retrieve(entity.LogicalName, entity.Id, new ColumnSet(true));
        }

        public Entity GetEntity(EntityReference entity)
        {
            return service.Retrieve(entity.LogicalName, entity.Id, new ColumnSet(true));
        }

        public Entity GetEntity(EntityReference entity, string[] columns)
        {
            return service.Retrieve(entity.LogicalName, entity.Id, new ColumnSet(columns));
        }
        public Entity GetEntity(EntityReference entity, ColumnSet columns)
        {
            return service.Retrieve(entity.LogicalName, entity.Id, columns);
        }

        public bool AccessTeamExists(EntityReference record, Guid teamTemplateId)
        {
            var q = new QueryExpression("team");
            AddCriteria(q, "teamtype", 1);
            AddCriteria(q, "teamtemplateid", teamTemplateId);
            AddCriteria(q, "regardingobjectid", record.Id);

            return GetMultiple(q).Any();

        }


        public void DisablePluginStep(string stepName)
        {
            trace.Trace($"disable the {stepName} plugin");
            var q = new QueryExpression("sdkmessageprocessingstep");
            AddCriteria(q, "name", stepName);
            var step = GetMultiple(q).Single();

            var ssr = new SetStateRequest();
            ssr.EntityMoniker = new EntityReference("sdkmessageprocessingstep", step.Id);
            ssr.State = new OptionSetValue(1);
            ssr.Status = new OptionSetValue(2);
            service.Execute(ssr);
            trace.Trace("plugin step disabled");
        }


        public void EnablePluginStep(string stepName)
        {
            trace.Trace($"enable the {stepName} plugin");
            var q = new QueryExpression("sdkmessageprocessingstep");
            AddCriteria(q, "name", stepName);
            var step = GetMultiple(q).Single();

            var ssr = new SetStateRequest();
            ssr.EntityMoniker = new EntityReference("sdkmessageprocessingstep", step.Id);
            ssr.State = new OptionSetValue(0);
            ssr.Status = new OptionSetValue(1);
            service.Execute(ssr);
            trace.Trace("plugin step enabled");
        }

        public string GetEntityLogicalName(int entityTypeCode)
        {
            var entityFilter = new MetadataFilterExpression(LogicalOperator.And);
            entityFilter.Conditions.Add(new MetadataConditionExpression("ObjectTypeCode ", MetadataConditionOperator.Equals, entityTypeCode));
            var propertyExpression = new MetadataPropertiesExpression { AllProperties = false };
            propertyExpression.PropertyNames.Add("LogicalName");
            var entityQueryExpression = new EntityQueryExpression()
            {
                Criteria = entityFilter,
                Properties = propertyExpression
            };

            var retrieveMetadataChangesRequest = new RetrieveMetadataChangesRequest()
            {
                Query = entityQueryExpression
            };

            var response = (RetrieveMetadataChangesResponse)service.Execute(retrieveMetadataChangesRequest);

            if (response.EntityMetadata.Count == 1)
            {
                return response.EntityMetadata[0].LogicalName;
            }
            return null;
        }
        public Entity GetEntity(string entityName, string fieldName, object fieldValue)
        {
            var query = new QueryExpression(entityName);
            query.Criteria.AddCondition(fieldName, ConditionOperator.Equal, fieldValue);
            query.ColumnSet = new ColumnSet(true);
            return GetMultiple(query).SingleOrDefault();

        }
        public List<Entity> GetManyToManyEntity(Guid fieldValue, string relatedEntity, string manyToManyRelationshipTable, string relatedEntityId, string entityId)
        {
            var query = new QueryExpression(relatedEntity);
            query.ColumnSet = new ColumnSet(true);
            var link = new LinkEntity(relatedEntity, manyToManyRelationshipTable, relatedEntityId, relatedEntityId, JoinOperator.Inner);
            link.LinkCriteria.AddCondition(entityId, ConditionOperator.Equal, fieldValue);
            query.LinkEntities.Add(link);
            var link2 = GetMultiple(query);
            return link2;
        }
        public List<Entity> GetMultiple(string fetchXml)
        {
            var fetchReq = new FetchXmlToQueryExpressionRequest();
            fetchReq.FetchXml = fetchXml;

            var res = (FetchXmlToQueryExpressionResponse)service.Execute(fetchReq);

            return GetMultiple(res.Query);
        }

        public void UpdateMultipleAttributes(string entityName, Guid entityId, Dictionary<string, object> attributes)
        {

            UpdateMultipleAttributes(new EntityReference(entityName, entityId), attributes);
        }
        public void UpdateMultipleAttributes(Entity e, Dictionary<string, object> attributes)
        {
            UpdateMultipleAttributes(e.ToEntityReference(), attributes);
        }

        public void UpdateMultipleAttributes(EntityReference e, Dictionary<string, object> attributes)
        {
            //using this format rather than constructor for CRM2011 compatibility
            var entity = new Entity { LogicalName = e.LogicalName, Id = e.Id };
            foreach (var kvp in attributes)
            {
                entity[kvp.Key] = kvp.Value;
            }
            service.Update(entity);

        }

        public void UpdateSingleAttribute(string entityName, Guid entityId, string attributeName, object attributeValue)
        {
            UpdateSingleAttribute(new EntityReference(entityName, entityId), attributeName, attributeValue);
        }

        public void UpdateSingleAttribute(Entity e, string attributeName, object attributeValue)
        {
            UpdateSingleAttribute(e.ToEntityReference(), attributeName, attributeValue);
        }

        public void UpdateSingleAttribute(EntityReference e, string attributeName, object attributeValue)
        {
            //using this format rather than constructor for CRM2011 compatibility
            var entity = new Entity { LogicalName = e.LogicalName, Id = e.Id };
            entity[attributeName] = attributeValue;
            service.Update(entity);

        }

        public bool CurrentUserIsSystemAdmin()
        {
            return IsSystemAdmin(context.InitiatingUserId);
        }

        public bool IsSystemAdmin(Guid userId)
        {
            // All MS Dynamics CRM instances share the same System Admin role GUID.
            // Hence, we can hardode it as this will not represent a security issue
            Guid adminId = new Guid("627090FF-40A3-4053-8790-584EDC5BE201");

            var q = new QueryExpression("role");
            q.Criteria.AddCondition("roletemplateid", ConditionOperator.Equal, adminId);
            var link = q.AddLink("systemuserroles", "roleid", "roleid");
            link.LinkCriteria.AddCondition("systemuserid", ConditionOperator.Equal, userId);
            return GetMultiple(q).Count > 0;
        }

        public List<Entity> GetMultiple(QueryBase query)
        {

            var resp = service.RetrieveMultiple(query);
            if (resp != null && resp.Entities != null)
            {
                return resp.Entities.ToList();
            }
            else
            {
                return new List<Entity>();
            }
        }

        public void AddCriteria(QueryExpression q, string fieldName, object value)
        {
            q.Criteria.AddCondition(fieldName, ConditionOperator.Equal, value);
        }

        public List<T> GetMultiple<T>(QueryBase query)
        {
            var resp = service.RetrieveMultiple(query);
            if (resp != null && resp.Entities != null)
            {
                return resp.Entities.Cast<T>().ToList();
            }
            else
            {
                return new List<T>();
            }
        }

        public string GetOptionsetText(string optionSetName, int optionSetValue, string entityName = "")
        {
            try
            {
                var options = GetOptionSetMetadata(optionSetName, entityName);
                IList<OptionMetadata> optionsList = (from o in options.Options
                                                     where o.Value != null && o.Value.Value == optionSetValue
                                                     select o).ToList();
                var optionSetLabel = (optionsList.Count > 0) ? optionsList.First().Label.UserLocalizedLabel.Label : "(Value No Found)";
                return optionSetLabel;
            }
            catch (Exception)
            {
                throw;
            }
        }
        public int GetOptionsetValue(string optionSetName, string optionSetText, string entityName = "")
        {
            try
            {
                var options = GetOptionSetMetadata(optionSetName, entityName);
                IList<OptionMetadata> optionsList = (from o in options.Options
                                                     where o.Value != null && o.Label.UserLocalizedLabel.Label == optionSetText
                                                     select o).ToList();
                var optionSetLabel = (optionsList.Count > 0) ? optionsList.First().Value.Value : 0;
                return optionSetLabel;
            }
            catch (Exception)
            {
                throw;
            }
        }

        public Guid Create(Entity entity)
        {
            return service.Create(entity);
        }

        public void DeleteEntity(Entity entity)
        {
            service.Delete(entity.LogicalName, entity.Id);
        }

        public List<Entity> GetAll(QueryExpression query)
        {
            var entities = new List<Entity>();

            query.PageInfo = new PagingInfo();
            query.PageInfo.Count = 5000;
            query.PageInfo.PagingCookie = null;
            query.PageInfo.PageNumber = 1;
            var res = service.RetrieveMultiple(query);
            entities.AddRange(res.Entities);
            while (res.MoreRecords == true)
            {
                query.PageInfo.PageNumber++;
                query.PageInfo.PagingCookie = res.PagingCookie;
                res = service.RetrieveMultiple(query);
                entities.AddRange(res.Entities);
            }

            return entities;
        }
        public List<Entity> GetAll(string entityName)
        {
            var entities = new List<Entity>();

            var query = new QueryExpression(entityName);
            query.ColumnSet = new ColumnSet(true);

            query.PageInfo = new PagingInfo();
            query.PageInfo.Count = 5000;
            query.PageInfo.PagingCookie = null;
            query.PageInfo.PageNumber = 1;
            var res = service.RetrieveMultiple(query);
            entities.AddRange(res.Entities);
            while (res.MoreRecords == true)
            {
                query.PageInfo.PageNumber++;
                query.PageInfo.PagingCookie = res.PagingCookie;
                res = service.RetrieveMultiple(query);
                entities.AddRange(res.Entities);
            }

            return entities;
        }


        public void DeactivateEntity(Entity entity)
        {
            DeactivateEntity(entity.ToEntityReference());
        }

        public void DeactivateEntity(EntityReference entityRef)
        {
            SetStateRequest setState = new SetStateRequest();
            setState.EntityMoniker = entityRef;
            setState.State = new OptionSetValue();
            setState.State.Value = 1;
            setState.Status = new OptionSetValue();
            setState.Status.Value = 2;
            SetStateResponse setStateResponse = (SetStateResponse)service.Execute(setState);
        }


        public void ActivateEntity(Entity entity)
        {
            ActivateEntity(entity.ToEntityReference());
        }

        public void ActivateEntity(EntityReference entityRef)
        {
            SetStateRequest setState = new SetStateRequest();
            setState.EntityMoniker = entityRef;
            setState.State = new OptionSetValue();
            setState.State.Value = 0;
            setState.Status = new OptionSetValue();
            setState.Status.Value = 1;
            SetStateResponse setStateResponse = (SetStateResponse)service.Execute(setState);
        }

        public OptionSetMetadata GetOptionSetMetadata(string optionsetName, string entityName = "")
        {

            try
            {
                OptionSetMetadata optionSetMetadata = null;

                if (string.IsNullOrEmpty(entityName))
                {
                    var retrieveOptionSetRequest = new RetrieveOptionSetRequest
                    {
                        Name = optionsetName,
                        RetrieveAsIfPublished = true
                    };

                    // Execute the request.
                    var retrieveOptionSetResponse = (RetrieveOptionSetResponse)service.Execute(retrieveOptionSetRequest);

                    // Access the retrieved OptionSetMetadata.
                    optionSetMetadata = (OptionSetMetadata)retrieveOptionSetResponse.OptionSetMetadata;
                }
                else
                {
                    var request = new RetrieveAttributeRequest
                    {
                        EntityLogicalName = entityName,
                        LogicalName = optionsetName,
                        RetrieveAsIfPublished = true
                    };

                    var resp = (RetrieveAttributeResponse)service.Execute(request);

                    if (optionsetName.Contains("statecode"))
                    {
                        var retrievedPicklistAttributeMetadata = (StateAttributeMetadata)resp.AttributeMetadata;
                        optionSetMetadata = retrievedPicklistAttributeMetadata.OptionSet;
                    }
                    else if (optionsetName.Contains("statuscode"))
                    {
                        var retrievedPicklistAttributeMetadata = (StatusAttributeMetadata)resp.AttributeMetadata;
                        optionSetMetadata = retrievedPicklistAttributeMetadata.OptionSet;
                    }
                    else
                    {
                        try
                        {
                            var retrievedPicklistAttributeMetadata = (PicklistAttributeMetadata)resp.AttributeMetadata;
                            optionSetMetadata = retrievedPicklistAttributeMetadata.OptionSet;
                        }
                        catch (Exception)
                        {

                            //return nothing
                        }

                    }
                }

                return optionSetMetadata;
            }
            catch (Exception)
            {
                throw;
            }
        }
        /// <summary>
        /// ////////////////////////////////////////////////////////////////////////////////////// START OF HELPER
        /// </summary>
        /// <param name="s"></param>

        public void log(string s)
        {
            Trace(s);
        }

        public void Trace(string s)
        {
            trace.Trace("[" + caller + "] " + s);
        }

        public void AddRetrievedEntity(Entity e)
        {
            this.Trace("added entity : " + e.LogicalName);
            entities.Add(e);
        }

        // Get a new instance of an entity to use for patch updates
        public Entity GetNewEntity(Entity e)
        {
            Entity entity = new Entity(e.LogicalName);
            entity.Id = e.Id;
            return entity;
        }

        public Entity GetNewEntity()
        {
            return GetNewEntity(targetImage);
        }



        public void OutputAttribute(Entity e, string attribute_name)
        {
            var attribute = e[attribute_name];
            if (attribute == null)
            {
                this.Trace("Attribute [" + attribute_name + "] is NULL");
                return;
            }

            switch (attribute.GetType().Name)
            {
                case "Money":
                    var m = attribute as Money;
                    this.Trace("Attribute [" + attribute_name + "] [" + m.Value.ToString() + "]");
                    break;
                case "EntityReference":
                    var er = attribute as EntityReference;
                    Trace("Attribute [" + attribute_name + "] [" + er.Id.ToString() + "] [" + er.LogicalName.ToString() + "] [" + er.Name + "]");
                    break;
                case "OptionSetValue":
                    var os = attribute as OptionSetValue;
                    Trace("Attribute [" + attribute_name + "] [" + os.Value + "]");
                    break;
                default:
                    Trace("Attribute [" + attribute_name + "] [" + attribute.ToString() + "]");
                    break;
            }
        }


        public void OutputEntityAttributes(Entity e, string tag = "")
        {
            this.Trace("outputting entity [" + tag + "] : " + e.LogicalName + "\n-----------------");
            foreach (KeyValuePair<String, Object> kvp in e.Attributes)
            {
                if (kvp.Value != null)
                {
                    OutputAttribute(e, kvp.Key);
                }
                else
                    this.Trace("[" + kvp.Key + "]");
            }
            this.Trace("-----------------");
        }

        public void OutputRetrievedEntityData()
        {
            this.Trace("output retrieved entity data");
            foreach (Entity e in entities)
            {
                OutputEntityAttributes(e);
            }
        }

        public bool ResultsHaveEntries(EntityCollection result)
        {
            if (result != null & result.Entities != null & result.Entities.Count > 0)
                return true;

            return false;
        }

        public Guid CreateEntity(Entity e)
        {
            this.Trace("CreateEntity : " + e.LogicalName);
            OutputEntityAttributes(e);
            this.Trace("Calling create command");
            Guid id = service.Create(e);
            this.Trace("created : " + id.ToString());
            return id;
        }



        public Entity GetContextEntity(IPluginExecutionContext context, int t)
        {
            Entity e = null;
            try
            {
                switch (t)
                {
                    case ReddishGreenHelperContext.TARGET:
                        e = (Entity)context.InputParameters["Target"];
                        if (!this.obfuscate)
                            OutputEntityAttributes(e, "target");
                        break;
                    case ReddishGreenHelperContext.POSTIMAGE:
                        e = (Entity)context.PostEntityImages["PostImage"];
                        if (!this.obfuscate)
                            OutputEntityAttributes(e, "postimage");
                        break;

                    case ReddishGreenHelperContext.PREIMAGE:
                        e = (Entity)context.PreEntityImages["PreImage"];
                        if (!this.obfuscate)
                            OutputEntityAttributes(e, "preimage");
                        break;

                    default:
                        throw new Exception("Unknown image type");

                }
            }
            catch (Exception ex)
            {
                throw new InvalidPluginExecutionException("Failed to get image : " + t.ToString() + " : " + ex.Message);
            }

            return e;
        }

        public Entity Retrieve(string entity_name, Guid id, ColumnSet column_set = null)
        {
            if (column_set == null)
                column_set = new ColumnSet(true);

            Trace("Retrieving : " + entity_name + " : " + id.ToString());
            Entity e = (Entity)service.Retrieve(entity_name, id, column_set);
            //OutputEntityAttributes(e, "retrieved");
            return e;
        }

        public Entity RetrieveOptional(string entity_name, Entity entity_reference_source, string entity_reference_field, ColumnSet column_set = null)
        {
            Entity e = null;

            if (entity_reference_source.Attributes.Contains(entity_reference_field))
            {
                EntityReference ent_ref = entity_reference_source.GetAttributeValue<EntityReference>(entity_reference_field);
                e = Retrieve(entity_name, ent_ref.Id, column_set);
            }
            else
            {
                Trace("Entity field doesn't exist : " + entity_reference_field);
            }

            return e;
        }

        public Entity RetrieveRequired(string entity_name, Entity entity_reference_source, string entity_reference_field, ColumnSet column_set = null)
        {
            Entity e = RetrieveOptional(entity_name, entity_reference_source, entity_reference_field, column_set);
            if (e == null)
            {
                OutputEntityAttributes(e);
                throw new InvalidPluginExecutionException("Unable to retrieve : " + entity_name);
            }

            return e;
        }

        public T GetOptionalAttributeValue<T>(string attributeName, Entity image = null, bool obfuscate = false)
        {
            if (targetImage != null && targetImage.Contains(attributeName))
                return GetAttributeValue<T>(targetImage, attributeName, image, false, obfuscate);

            if (preImage != null)
                return GetAttributeValue<T>(preImage, attributeName, image, false, obfuscate);

            return GetAttributeValue<T>(targetImage, attributeName, image, false, obfuscate);
        }

        public T GetMandatoryAttributeValue<T>(string attributeName, Entity image = null, bool obfuscate = false)
        {
            if (targetImage != null && targetImage.Contains(attributeName))
                return GetAttributeValue<T>(targetImage, attributeName, image, true, obfuscate);

            if (preImage != null)
                return GetAttributeValue<T>(preImage, attributeName, image, true, obfuscate);

            return GetAttributeValue<T>(targetImage, attributeName, image, true, obfuscate);
        }

        public T GetOptionalAttributeValue<T>(Entity entity, string attributeName, Entity image = null, bool obfuscate = false)
        {
            return GetAttributeValue<T>(entity, attributeName, image, false, obfuscate);
        }


        public T GetMandatoryAttributeValue<T>(Entity entity, string attributeName, Entity image = null, bool obfuscate = false)
        {
            return GetAttributeValue<T>(entity, attributeName, image, true, obfuscate);
        }

        public T GetAttributeValue<T>(Entity entity, string attributeName, Entity image = null, bool required = true, bool obfuscate = false)
        {
            if (entity.Attributes.Contains(attributeName))
            {
                if (!obfuscate)
                    OutputAttribute(entity, attributeName);
                return entity.GetAttributeValue<T>(attributeName);
            }
            else if (image != null && image.Attributes.Contains(attributeName))
            {
                if (!obfuscate)
                    OutputAttribute(image, attributeName);
                return image.GetAttributeValue<T>(attributeName);
            }
            else if (required)
            {
                Trace("Failed to get mandatory attribute from : " + entity.LogicalName);
                if (!obfuscate)
                    OutputEntityAttributes(entity, "entity");
                if (image != null && !obfuscate) OutputEntityAttributes(image, "image");
                throw new InvalidPluginExecutionException("Mandatory Dictionary key does not exist : " + attributeName);
            }
            return default(T);
        }

        public T GetOldValue<T>(string attributeName, bool obfuscate = false)
        {
            return GetMandatoryAttributeValue<T>(preImage, attributeName, null, obfuscate);
        }

        public T GetNewValue<T>(string attributeName, bool obfuscate = false)
        {
            return GetMandatoryAttributeValue<T>(attributeName, null, obfuscate);
        }

        public void Post(Entity target, EntityReference related, int postSource, string message)
        {
            RetrieveEntityRequest EntityRequest = new RetrieveEntityRequest();
            EntityRequest.LogicalName = target.LogicalName;
            EntityRequest.EntityFilters = EntityFilters.All;
            RetrieveEntityResponse responseent = (RetrieveEntityResponse)service.Execute(EntityRequest);
            EntityMetadata ent = (EntityMetadata)responseent.EntityMetadata;
            string ObjectTypeCode = ent.ObjectTypeCode.ToString();
            string target_label = ent.DisplayName.LocalizedLabels[0].Label;

            var post = new Entity("post");
            post["text"] = message + " @[" + ObjectTypeCode + "," + target.Id.ToString() + ",\"" + target_label + "\"]";
            post["regardingobjectid"] = related;
            post["source"] = new OptionSetValue(postSource);
            Trace("Creating post : " + post["text"]);
            service.Create(post);
        }

        public void SimplePost(EntityReference related, int postSource, string message)
        {
            var post = new Entity("post");
            post["text"] = message;
            post["regardingobjectid"] = related;
            post["source"] = new OptionSetValue(postSource);
            Trace("Creating post : " + post["text"]);
            service.Create(post);
        }

        public string GetObjectReferenceForPost()
        {
            return GetObjectReferenceForPost(targetImage);
        }



        public string GetObjectReferenceForPost(Entity entity)
        {
            RetrieveEntityRequest EntityRequest = new RetrieveEntityRequest();
            EntityRequest.LogicalName = entity.LogicalName;
            EntityRequest.EntityFilters = EntityFilters.All;
            RetrieveEntityResponse responseent = (RetrieveEntityResponse)service.Execute(EntityRequest);
            EntityMetadata ent = (EntityMetadata)responseent.EntityMetadata;
            string ObjectTypeCode = ent.ObjectTypeCode.ToString();
            string target_label = ent.DisplayName.LocalizedLabels[0].Label;

            string reference = " @[" + ObjectTypeCode + "," + entity.Id.ToString() + ",\"" + target_label + "\"]";

            return reference;
        }

        public void UpdateSingleFieldIfChanged<T>(Entity e, string field_name, T field_value, bool obfuscate = false)
        {
            Entity entity_update = GetNewEntity(e);
            entity_update[field_name] = field_value;
            if (!ContainsField(e, field_name) || !e.GetAttributeValue<T>(field_name).Equals(field_value))
            {
                service.Update(entity_update);
            }
            else
            {
                Trace("Field " + field_name + " unchanged so not updating");
                if (!obfuscate)
                    OutputAttribute(e, field_name);
            }
        }

        public void UpdateSingleFieldIfChanged<T>(string field_name, T field_value, bool obfuscate = false)
        {
            Entity entity_update = GetNewEntity();
            entity_update[field_name] = field_value;
            if (!ContainsField(field_name) || !GetMandatoryAttributeValue<T>(field_name, null, obfuscate).Equals(field_value))
            {
                service.Update(entity_update);
            }
            else
            {
                Trace("Field " + field_name + " unchanged so not updating");
            }
        }

        public EntityCollection GetLinkedEntities(Guid sourceGuid, string linkedEntityName, string sourceEntityFieldname, ColumnSet column_set = null)
        {
            if (column_set == null) column_set = new ColumnSet(true);

            QueryExpression q = new QueryExpression(linkedEntityName);
            q.ColumnSet = column_set;
            q.Criteria.AddCondition(sourceEntityFieldname, ConditionOperator.Equal, sourceGuid);
            EntityCollection q_result = service.RetrieveMultiple(q);

            return q_result;
        }

        public EntityCollection GetLinkedEntities(string linkedEntityName, string sourceEntityFieldname, ColumnSet column_set = null)
        {
            return GetLinkedEntities(targetImage.Id, linkedEntityName, sourceEntityFieldname, column_set);
        }

        public void MakeRecordInactive(Entity e)
        {
            SetStateRequest setStateRequest = new SetStateRequest()
            {
                EntityMoniker = new EntityReference
                {
                    Id = e.Id,
                    LogicalName = e.LogicalName,
                },
                State = new OptionSetValue(1),
                Status = new OptionSetValue(2)
            };
            service.Execute(setStateRequest);
        }

        public void MakeRecordInactive()
        {
            MakeRecordInactive(targetImage);
        }

        public bool HasLinkedEntity(Guid sourceGuid, string linkedEntityName, string sourceEntityFieldname)
        {
            EntityCollection q_result = GetLinkedEntities(sourceGuid, linkedEntityName, sourceEntityFieldname);
            return ResultsHaveEntries(q_result);
        }

        public bool HasLinkedEntity(string linkedEntityName, string sourceEntityFieldname)
        {
            return HasLinkedEntity(targetImage.Id, linkedEntityName, sourceEntityFieldname);
        }

        public string ProcessCommaSeperatedList(string error)
        {
            error = error.Substring(0, error.Length - 2);
            if ((error.Split(',').Length - 1) > 0)
            {
                error += " are";
                int place = error.LastIndexOf(",");

                if (place > -1)
                    error = error.Remove(place, 1).Insert(place, " and");

            }
            else
                error += " is";

            return error;
        }

        public bool FieldUpdated(string attribute)
        {
            return targetImage.Contains(attribute);
        }

        public bool ContainsField(string attribute)
        {
            if (targetImage != null && targetImage.Contains(attribute))
            {
                if (targetImage[attribute] == null)
                {
                    this.Trace("Value has been removed in target, so considered not contained [" + attribute + "]");
                    return false;
                }
                return true;
            }

            if (preImage != null && preImage.Contains(attribute))
                return true;

            return false;
        }


        public bool ContainsField(Entity e, string attribute)
        {
            if (e != null && e.Contains(attribute))
            {
                if (e[attribute] == null)
                {
                    this.Trace("Value has been removed in entity, so considered not contained [" + attribute + "]");
                    return false;
                }
                return true;
            }
            return false;
        }

        public string GetFormattedValue(string attributeName)
        {
            if (postImage != null && postImage.FormattedValues.Contains(attributeName))
            {
                Trace("Post Attribute: [" + attributeName + "] [" + postImage.FormattedValues[attributeName] + "]");
                return postImage.FormattedValues[attributeName];
            }
            else if (targetImage != null && targetImage.FormattedValues.Contains(attributeName))
            {
                Trace("Tgt Attribute: [" + attributeName + "] [" + targetImage.FormattedValues[attributeName] + "]");
                return targetImage.FormattedValues[attributeName];
            }
            else if (preImage != null && preImage.FormattedValues.Contains(attributeName))
            {
                Trace("Pre Attribute: [" + attributeName + "] [" + preImage.FormattedValues[attributeName] + "]");
                return preImage.FormattedValues[attributeName];
            }
            else
            {
                Trace("Unable to get formatted value [" + attributeName + "]");
                return null;
            }
        }

        public bool FieldsMatch(Entity src, Entity tgt, string field)
        {
            bool resourcesMatch = false;
            log($"Fields match {field}");
            if (ContainsField(tgt, field))
            {
                if (!ContainsField(src, field))
                {
                    log($"field is in target, but not source");
                    resourcesMatch = false;
                }
                else
                {
                    switch (src[field].GetType().Name)
                    {
                        case "Money":
                            var srcFieldm = src[field] as Money;
                            var tgtFieldm = tgt[field] as Money;
                            resourcesMatch = (srcFieldm.Value == tgtFieldm.Value);
                            if (!resourcesMatch)
                                log($"Values don't match : {srcFieldm.Value} {tgtFieldm.Value}");
                            break;
                        case "EntityReference":
                            var srcFielder = src[field] as EntityReference;
                            var tgtFielder = tgt[field] as EntityReference;
                            resourcesMatch = (srcFielder.Id == tgtFielder.Id);
                            if (!resourcesMatch)
                                log($"Values don't match : {srcFielder.Id} {tgtFielder.Id}");
                            break;
                        case "OptionSetValue":
                            var srcFieldos = src[field] as OptionSetValue;
                            var tgtFieldos = tgt[field] as OptionSetValue;
                            resourcesMatch = (srcFieldos.Value == tgtFieldos.Value);
                            if (!resourcesMatch)
                                log($"Values don't match : {srcFieldos.Value} {tgtFieldos.Value}");
                            break;
                        default:
                            log($"Using default {src[field].GetType().Name}");
                            resourcesMatch = (src[field] == tgt[field]);
                            break;
                    }
                }
            }
            else if (!ContainsField(src, field))
            {
                log($"field doesn't exist in either entity : {field}");
                resourcesMatch = true;
            }

            log($"returning : {resourcesMatch}");

            return resourcesMatch;
        }

        public string RSAEncrypt(string input, string public_key)
        {
            RSACryptoServiceProvider csp = new RSACryptoServiceProvider(2048);
            csp.FromXmlString(public_key);

            byte[] plainText = Encoding.ASCII.GetBytes(input);
            byte[] cipherText = csp.Encrypt(plainText, false);

            return Convert.ToBase64String(cipherText);
        }
    }
}
